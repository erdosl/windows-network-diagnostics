. (Join-Path $PSScriptRoot 'Dns.ps1')

function Get-ProbeRemainingMilliseconds {
    param([Diagnostics.Stopwatch]$Watch, [int]$TimeoutMs, [string]$Stage)
    $remaining = $TimeoutMs - $Watch.ElapsedMilliseconds
    if ($remaining -le 0) { throw [TimeoutException]::new("Probe budget exhausted during $Stage.") }
    [int]$remaining
}

function Test-ProbeTimeoutException {
    param([Exception]$Exception)
    while ($null -ne $Exception) {
        if ($Exception -is [TimeoutException] -or
            ($Exception -is [Net.Sockets.SocketException] -and $Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut)) { return $true }
        $Exception = $Exception.InnerException
    }
    $false
}

function Read-ProbeHttpStatus {
    param($Stream, [Diagnostics.Stopwatch]$Watch, [int]$TimeoutMs,$Evidence)
    $budget=@{Bytes=0;Informational=0}
    $readLine={
        $line=[Text.StringBuilder]::new();$cr=$false
        while($true){
            $remaining=Get-ProbeRemainingMilliseconds $Watch $TimeoutMs 'HTTP response headers'
            if($Stream -isnot [IO.Stream] -or $Stream.CanTimeout){$Stream.ReadTimeout=$remaining}
            $next=$Stream.ReadByte();$budget.Bytes++
            if($budget.Bytes -gt 32768){throw [IO.InvalidDataException]::new('HTTP total header limit exceeded (32768 bytes).')}
            if($next -lt 0){throw [IO.EndOfStreamException]::new('EOF before complete final HTTP headers.')}
            if($cr){if($next -ne 10){throw [IO.InvalidDataException]::new('HTTP header line requires CRLF.')};return $line.ToString()}
            if($next -eq 13){$cr=$true;continue}
            if($next -eq 10 -or ($next -lt 32 -and $next -ne 9) -or $next -eq 127){throw [IO.InvalidDataException]::new('Invalid HTTP header character.')}
            $null=$line.Append([char]$next)
            if($line.Length -gt 4096){throw [IO.InvalidDataException]::new('HTTP line limit exceeded (4096 bytes).')}
        }
    }
    while($true){
        $status=& $readLine
        if($status -notmatch '^HTTP/1\.[01] ([1-5][0-9]{2}) [\x20-\x7e\x80-\xff]*$'){throw [IO.InvalidDataException]::new('Invalid HTTP status line or status code.')}
        $code=[int]$Matches[1]
        if($code -lt 200){
            $budget.Informational++
            if($Evidence){$Evidence.InformationalStatuses+= $status}
            if($code -eq 101){throw [NotSupportedException]::new('HTTP 101 protocol upgrade is unexpected for this HEAD probe.')}
            if($budget.Informational -gt 8){throw [IO.InvalidDataException]::new('HTTP informational response limit exceeded (8).')}
        }elseif($Evidence){$Evidence.HttpStatusLine=$status;$Evidence.FinalStatusCode=$code}
        do {
            $header=& $readLine
            if($header -and $header -notmatch '^[!#$%&''*+.^_`|~0-9A-Za-z-]+:[\x09\x20-\x7e\x80-\xff]*$'){throw [IO.InvalidDataException]::new('Malformed HTTP header.')}
        }while($header.Length -gt 0)
        if($code -ge 200){return $status}
    }
}

function Get-ProbeHttpOutcome {
    param([string]$StatusLine)
    if ($StatusLine -notmatch '^HTTP/1\.[01] ([2-5][0-9]{2}) [\x20-\x7e\x80-\xff]*$') { throw 'Invalid or missing final HTTP response status line.' }
    if ([int]$Matches[1] -ge 400) { 'HttpError' } else { 'Success' }
}

function New-ProbeTcpClient {
    param([Net.Sockets.AddressFamily]$AddressFamily)
    [Net.Sockets.TcpClient]::new($AddressFamily)
}

function Set-ProbeInterfaceBinding {
    param($Client,[int]$RequestedInterfaceIndex,[string]$RequestedSourceAddress,[Net.Sockets.AddressFamily]$Family)
    $source=$null
    if(-not [Net.IPAddress]::TryParse($RequestedSourceAddress,[ref]$source) -or $source.AddressFamily -ne $Family){throw [NotSupportedException]::new('Requested source address and destination families differ or source is invalid.')}
    $matches=@(Get-NetIPAddress -IPAddress $source.ToString() -ErrorAction Stop)
    if($matches.Count -ne 1 -or $matches[0].InterfaceIndex -ne $RequestedInterfaceIndex){throw [NotSupportedException]::new('Requested source is not uniquely assigned to the requested interface.')}
    try{
        $level=[Net.Sockets.SocketOptionLevel]::IP;$value=[Net.IPAddress]::HostToNetworkOrder($RequestedInterfaceIndex)
        if($Family -eq [Net.Sockets.AddressFamily]::InterNetworkV6){$level=[Net.Sockets.SocketOptionLevel]::IPv6;$value=$RequestedInterfaceIndex}
        # Windows IP_UNICAST_IF / IPV6_UNICAST_IF = 31; IPv4 uses network byte order.
        $Client.Client.SetSocketOption($level,[Net.Sockets.SocketOptionName]31,[int]$value)
        $Client.Client.Bind([Net.IPEndPoint]::new($source,0))
    }catch{throw [NotSupportedException]::new('Requested socket binding could not be established; no unbound fallback.', $_.Exception)}
}

function New-ProbeTlsStream {
    param($Stream)
    [Net.Security.SslStream]::new($Stream, $false)
}

function Invoke-ProbeTlsHandshake {
    param($Stream, [string]$HostName, [Diagnostics.Stopwatch]$Watch, [int]$TimeoutMs)
    $null = Get-ProbeRemainingMilliseconds $Watch $TimeoutMs 'TLS negotiation'
    $tls = $Stream.BeginAuthenticateAsClient($HostName, $null, $null)
    try {
        if (-not $tls.AsyncWaitHandle.WaitOne((Get-ProbeRemainingMilliseconds $Watch $TimeoutMs 'TLS negotiation'))) {
            throw [TimeoutException]::new('TLS negotiation timed out.')
        }
        $Stream.EndAuthenticateAsClient($tls)
    } finally { $tls.AsyncWaitHandle.Close() }
}

function Get-RoutePrediction {
    param([string]$Destination)
    # Find-NetRoute returns the selected source address and route as separate objects.
    $raw = @(Find-NetRoute -RemoteIPAddress $Destination -ErrorAction Stop)
    [pscustomobject]@{ Attribution = 'RoutePrediction'; Destination = $Destination
        SourceAddresses = @($raw | Where-Object { $_.IPAddress } | Select-Object IPAddress,InterfaceIndex,InterfaceAlias,AddressFamily)
        Routes = @($raw | Where-Object { $_.DestinationPrefix } | Select-Object DestinationPrefix,NextHop,InterfaceIndex,RouteMetric,InterfaceMetric)
    }
}

function Invoke-ConnectivityProbe {
    param([ValidateSet('Resolve','Route','Gateway','DNS','TCP','HTTPS')][string]$Kind,
        [string]$Destination, [int]$Port = 443, [string]$QueryName = 'example.com', [string]$QueryType = 'A',
        [string]$Endpoint = 'https://example.com/', [int]$InterfaceIndex = 0, $DnsTarget = $null,
        [int]$RequestedInterfaceIndex=0,[string]$RequestedSourceAddress,
        [bool]$IncludeGatewayPing = $false, [ValidateRange(100,60000)][int]$TimeoutMs = 3000)
    $start = [DateTimeOffset]::Now
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $parsed = $null
    $family = 'Unresolved'
    if ([Net.IPAddress]::TryParse($Destination, [ref]$parsed)) { $family = $parsed.AddressFamily.ToString() }
    $result = [ordered]@{ Kind = $Kind; Destination = $Destination; Port = $Port; AddressFamily = $family
        StartedAt = $start.ToString('o'); CompletedAt = $null; DurationMs = 0; Outcome = 'Failed'; Error = $null
        DnsTarget = $DnsTarget; DnsError = $null; ProbeTimeoutMs = $TimeoutMs; TimeoutScope = $null; CompletedStages = @()
        RoutePrediction = $null; RouteError = $null; ObservedConnection = $null; Evidence = $null
        IntendedInterfaceIndex=$RequestedInterfaceIndex;RequestedSourceAddress=$RequestedSourceAddress;BindingStatus='Not requested' }
    $client = $null
    $ssl = $null
    try {
        if($RequestedInterfaceIndex -gt 0){
            $result.BindingStatus='Not established'
            if($Kind -in @('DNS','Gateway','Route')){throw [NotSupportedException]::new('This native probe does not guarantee requested source/interface binding; no unbound probe was sent.')}
        }
        if ($Kind -ne 'Resolve') {
            try { $result.RoutePrediction = Get-RoutePrediction $Destination }
            catch { $result.RouteError = $_.Exception.Message }
        }
        $null = Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'route setup'
        switch ($Kind) {
            'Resolve' {
                if($parsed){$result.Evidence=@([pscustomobject]@{IPAddress=$parsed.ToString();AddressFamily=$parsed.AddressFamily.ToString()});$result.Outcome='Success';break}
                $resolution = [Net.Dns]::BeginGetHostAddresses($Destination, $null, $null)
                try {
                    if (-not $resolution.AsyncWaitHandle.WaitOne((Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'name resolution'))) {
                        throw [TimeoutException]::new('Name resolution timed out.')
                    }
                    $resolvedAddresses = [Net.Dns]::EndGetHostAddresses($resolution)
                } finally { $resolution.AsyncWaitHandle.Close() }
                $addresses = @($resolvedAddresses | ForEach-Object {
                    [pscustomobject]@{ IPAddress = $_.ToString(); AddressFamily = $_.AddressFamily.ToString() }
                })
                $result.Evidence = $addresses
                if($RequestedInterfaceIndex){$result.BindingStatus='OS resolver preparation only; not an interface-bound DNS test'}
                $result.Outcome = 'Success'
            }
            'Route' {
                if ($null -eq $result.RoutePrediction) { throw $result.RouteError }
                $result.Outcome = 'Success'
            }
            'Gateway' {
                $result.Evidence = [pscustomobject]@{ ConfiguredInterfaceIndex = $InterfaceIndex; Neighbours = @(); NeighbourError = $null; ICMP = $null }
                try {
                    $result.Evidence.Neighbours = @(Get-NetNeighbor -InterfaceIndex $InterfaceIndex -IPAddress ($Destination -replace '%[0-9]+$','') -ErrorAction Stop |
                        Select-Object InterfaceIndex,IPAddress,LinkLayerAddress,State,AddressFamily)
                } catch { $result.Evidence.NeighbourError = $_.Exception.Message }
                $result.Outcome = $(if ($result.Evidence.NeighbourError) { 'Failed' } else { 'Observed' })
                if ($IncludeGatewayPing) {
                    $ping = [Net.NetworkInformation.Ping]::new()
                    try {
                        $reply = $ping.Send($Destination, (Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'ICMP'))
                        $result.Evidence.ICMP = [pscustomobject]@{ Status = $reply.Status.ToString(); RoundtripMs = $reply.RoundtripTime
                            Attribution = 'OS-selected path; source interface not observed'; Note = 'No reply does not prove the gateway is unreachable.' }
                        $result.Outcome = $(if ($reply.Status -eq 'Success') { 'Success' } elseif ($reply.Status -eq 'TimedOut') { 'TimedOut' } else { 'Failed' })
                        if ($result.Outcome -eq 'TimedOut') { $result.TimeoutScope = 'Probe' }
                    } finally { $ping.Dispose() }
                }
            }
            'DNS' {
                $result.Evidence = [pscustomobject]@{ Server = $Destination; QueryName = $QueryName; QueryType = $QueryType
                    Attribution = 'Server-specific query; route prediction only, source interface not observed'; Answers = @() }
                try { $result.Evidence.Answers = @(Resolve-DnsName -Name $QueryName -Type $QueryType -Server $Destination -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                    Select-Object Name,Type,TTL,Section,IPAddress,NameHost,Strings) }
                catch { $result.DnsError = Get-DnsErrorDetail $_; throw }
                $result.Outcome = 'Success'
            }
            { $_ -in @('TCP','HTTPS') } {
                if ($null -eq $parsed) { throw 'TCP/HTTPS workers require a resolved literal IP address.' }
                $client = New-ProbeTcpClient $parsed.AddressFamily
                if($RequestedInterfaceIndex -gt 0){
                    Set-ProbeInterfaceBinding $client $RequestedInterfaceIndex $RequestedSourceAddress $parsed.AddressFamily
                    $result.BindingStatus='Source bound; Windows outgoing interface option accepted'
                }
                $connect = $client.BeginConnect($parsed, $Port, $null, $null)
                try {
                    if (-not $connect.AsyncWaitHandle.WaitOne((Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'TCP connect'))) { throw [TimeoutException]::new('TCP connect timed out.') }
                    $client.EndConnect($connect)
                    $result.CompletedStages += 'TCP connect'
                } finally { $connect.AsyncWaitHandle.Close() }
                $local = $client.Client.LocalEndPoint
                $matching = @()
                $mappingError = $null
                try { $matching = @(Get-NetIPAddress -IPAddress $local.Address.ToString() -ErrorAction Stop |
                    Select-Object InterfaceIndex,InterfaceAlias,IPAddress,AddressFamily) }
                catch { $mappingError = $_.Exception.Message }
                $result.ObservedConnection = [pscustomobject]@{ Attribution = 'ObservedSocket'; LocalAddress = $local.Address.ToString()
                    LocalPort = $local.Port; RemoteAddress = $parsed.ToString(); RemotePort = $Port
                    InterfaceMatches = $matching; InterfaceMappingError = $mappingError
                    Note = 'Interface matches derive from the observed local address; ambiguous matches are retained.' }
                $result.Outcome = 'Success'
                if ($Kind -eq 'HTTPS') {
                    $uri = [uri]$Endpoint
                    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'HTTPS endpoint must have no user information, query, or fragment.' }
                    $result.Evidence = [pscustomobject]@{ Endpoint = $Endpoint; Method = 'HEAD'; HttpStatusLine = $null; FinalStatusCode=$null;InformationalStatuses=@(); TlsProtocol = $null
                        Proxy = 'Direct connection; system proxies and redirects are not used.' }
                    $stream = $client.GetStream()
                    $stream.ReadTimeout = Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'TLS setup'
                    $stream.WriteTimeout = Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'TLS setup'
                    $ssl = New-ProbeTlsStream $stream
                    # Default certificate validation; no credentials, client certificate, cookies, or overrides.
                    Invoke-ProbeTlsHandshake $ssl $uri.DnsSafeHost $watch $TimeoutMs
                    $result.CompletedStages += 'TLS negotiation'
                    $result.Evidence.TlsProtocol = $ssl.SslProtocol.ToString()
                    $ssl.WriteTimeout = Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'HTTP request'
                    $request = "HEAD $($uri.PathAndQuery) HTTP/1.1`r`nHost: $($uri.Authority)`r`nConnection: close`r`n`r`n"
                    $bytes = [Text.Encoding]::ASCII.GetBytes($request)
                    $ssl.Write($bytes, 0, $bytes.Length)
                    $result.CompletedStages += 'HTTP request'
                    $result.Evidence.HttpStatusLine = Read-ProbeHttpStatus $ssl $watch $TimeoutMs $result.Evidence
                    $result.Outcome = Get-ProbeHttpOutcome $result.Evidence.HttpStatusLine
                    $result.CompletedStages += 'HTTP response'
                }
            }
        }
        $null = Get-ProbeRemainingMilliseconds $watch $TimeoutMs 'probe completion'
    } catch {
        $result.Outcome = $(if ((Test-ProbeTimeoutException $_.Exception) -or $watch.ElapsedMilliseconds -ge $TimeoutMs) { 'TimedOut' } else { 'Failed' })
        if($_.Exception -is [NotSupportedException]){$result.Outcome='Unsupported'}
        if ($result.DnsError -and $result.DnsError.Classification -eq 'Timeout') { $result.Outcome = 'TimedOut'; $result.TimeoutScope = 'DNS' }
        elseif ($result.Outcome -eq 'TimedOut') { $result.TimeoutScope = 'Probe' }
        $result.Error = [pscustomobject]@{ Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category }
    } finally {
        if ($null -ne $ssl) { $ssl.Dispose() }
        if ($null -ne $client) { $client.Close() }
        $watch.Stop()
        $result.CompletedAt = [DateTimeOffset]::Now.ToString('o')
        $result.DurationMs = $watch.ElapsedMilliseconds
    }
    [pscustomobject]$result
}

function New-ProbeDefinition {
    param([string]$Name, [hashtable]$Arguments, [int]$TimeoutSeconds)
    # TimeoutSeconds here is the internal probe budget, not the worker deadline.
    if (-not $Arguments.ContainsKey('TimeoutMs')) { $Arguments.TimeoutMs = $TimeoutSeconds * 1000 }
    [pscustomobject]@{ Name = $Name; FunctionName = 'Invoke-ConnectivityProbe'; Arguments = $Arguments; TimeoutSeconds = $TimeoutSeconds }
}

function Get-ConnectivityDefinitions {
    param([object[]]$Checks, [string[]]$TcpDestinations, [int]$TcpPort, [string]$DnsQueryName,
        [string]$HttpsEndpoint, [int]$ProbeTimeoutSeconds, [bool]$IncludeGatewayPing, [bool]$IncludeLegacyDnsTargets = $false)
    $commonMs = [Math]::Min(60000, $ProbeTimeoutSeconds * 1000)
    $routes = @($Checks | Where-Object { $_.Name -eq 'Routes' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    foreach ($route in @($routes | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','::/0') -and $_.NextHop -notin @('0.0.0.0','::') } |
        Sort-Object InterfaceIndex,NextHop -Unique)) {
        $destination = [string]$route.NextHop
        if ($destination -like 'fe80:*' -and $destination -notlike '*%*') { $destination += '%' + $route.InterfaceIndex }
        New-ProbeDefinition "Connectivity:Gateway:$($route.InterfaceIndex):$destination" @{
            Kind = 'Gateway'; Destination = $destination; InterfaceIndex = [int]$route.InterfaceIndex; IncludeGatewayPing = $IncludeGatewayPing; TimeoutMs = $commonMs
        } $ProbeTimeoutSeconds
    }
    foreach ($target in @(Get-DnsTargetInventory $Checks $IncludeLegacyDnsTargets)) {
        foreach ($type in @('A','AAAA')) {
            $definition = New-ProbeDefinition "Connectivity:DNS:$($target.TargetId):$type" @{ Kind = 'DNS'; Destination = $target.Server; DnsTarget = $target; QueryName = $DnsQueryName; QueryType = $type; TimeoutMs = $commonMs } $ProbeTimeoutSeconds
            $definition | Add-Member NoteProperty SkipReason $(if ($target.Selection -eq 'Skipped') { $target.Reason } else { $null })
            $definition
        }
    }
    foreach ($destination in @($TcpDestinations | Select-Object -Unique)) {
        New-ProbeDefinition "Connectivity:Resolve:TCP:$destination" @{ Kind = 'Resolve'; Destination = $destination } $ProbeTimeoutSeconds
    }
    New-ProbeDefinition 'Connectivity:Resolve:HTTPS' @{ Kind = 'Resolve'; Destination = ([uri]$HttpsEndpoint).DnsSafeHost } $ProbeTimeoutSeconds
}
