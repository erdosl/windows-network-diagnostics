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
        [string]$Endpoint = 'https://example.com/', [int]$InterfaceIndex = 0,
        [bool]$IncludeGatewayPing = $false, [ValidateRange(100,60000)][int]$TimeoutMs = 3000)
    $start = [DateTimeOffset]::Now
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $parsed = $null
    $family = 'Unresolved'
    if ([Net.IPAddress]::TryParse($Destination, [ref]$parsed)) { $family = $parsed.AddressFamily.ToString() }
    $result = [ordered]@{ Kind = $Kind; Destination = $Destination; Port = $Port; AddressFamily = $family
        StartedAt = $start.ToString('o'); CompletedAt = $null; DurationMs = 0; Outcome = 'Failed'; Error = $null
        RoutePrediction = $null; RouteError = $null; ObservedConnection = $null; Evidence = $null }
    $client = $null
    $ssl = $null
    try {
        if ($Kind -ne 'Resolve') {
            try { $result.RoutePrediction = Get-RoutePrediction $Destination }
            catch { $result.RouteError = $_.Exception.Message }
        }
        switch ($Kind) {
            'Resolve' {
                $addresses = @([Net.Dns]::GetHostAddresses($Destination) | ForEach-Object {
                    [pscustomobject]@{ IPAddress = $_.ToString(); AddressFamily = $_.AddressFamily.ToString() }
                })
                $result.Evidence = $addresses
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
                        $reply = $ping.Send($Destination, $TimeoutMs)
                        $result.Evidence.ICMP = [pscustomobject]@{ Status = $reply.Status.ToString(); RoundtripMs = $reply.RoundtripTime
                            Attribution = 'OS-selected path; source interface not observed'; Note = 'No reply does not prove the gateway is unreachable.' }
                        $result.Outcome = $reply.Status.ToString()
                    } finally { $ping.Dispose() }
                }
            }
            'DNS' {
                $result.Evidence = [pscustomobject]@{ Server = $Destination; QueryName = $QueryName; QueryType = $QueryType
                    Attribution = 'Server-specific query; route prediction only, source interface not observed'; Answers = @() }
                $result.Evidence.Answers = @(Resolve-DnsName -Name $QueryName -Type $QueryType -Server $Destination -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                    Select-Object Name,Type,TTL,Section,IPAddress,NameHost,Strings)
                $result.Outcome = 'Success'
            }
            { $_ -in @('TCP','HTTPS') } {
                if ($null -eq $parsed) { throw 'TCP/HTTPS workers require a resolved literal IP address.' }
                $client = [Net.Sockets.TcpClient]::new($parsed.AddressFamily)
                $connect = $client.BeginConnect($parsed, $Port, $null, $null)
                try {
                    if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw [TimeoutException]::new('TCP connect timed out.') }
                    $client.EndConnect($connect)
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
                    $result.Evidence = [pscustomobject]@{ Endpoint = $Endpoint; Method = 'HEAD'; HttpStatusLine = $null; TlsProtocol = $null
                        Proxy = 'Direct connection; system proxies and redirects are not used.' }
                    $stream = $client.GetStream()
                    $stream.ReadTimeout = $TimeoutMs
                    $stream.WriteTimeout = $TimeoutMs
                    $ssl = [Net.Security.SslStream]::new($stream, $false)
                    # Default certificate validation; no credentials, client certificate, cookies, or overrides.
                    $tls = $ssl.BeginAuthenticateAsClient($uri.DnsSafeHost, $null, $null)
                    try {
                        if (-not $tls.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw [TimeoutException]::new('TLS negotiation timed out.') }
                        $ssl.EndAuthenticateAsClient($tls)
                    } finally { $tls.AsyncWaitHandle.Close() }
                    $ssl.ReadTimeout = $TimeoutMs
                    $ssl.WriteTimeout = $TimeoutMs
                    $request = "HEAD $($uri.PathAndQuery) HTTP/1.1`r`nHost: $($uri.Authority)`r`nConnection: close`r`n`r`n"
                    $bytes = [Text.Encoding]::ASCII.GetBytes($request)
                    $ssl.Write($bytes, 0, $bytes.Length)
                    $line = [Text.StringBuilder]::new()
                    while ($line.Length -lt 4096) {
                        $next = $ssl.ReadByte()
                        if ($next -eq -1 -or $next -eq 10) { break }
                        if ($next -ne 13) { $null = $line.Append([char]$next) }
                    }
                    $result.Evidence.HttpStatusLine = $line.ToString()
                    $result.Evidence.TlsProtocol = $ssl.SslProtocol.ToString()
                    if ($line.ToString() -notmatch '^HTTP/1\.[01] ([0-9]{3})') { throw 'Invalid or missing HTTP response status line.' }
                    if ([int]$Matches[1] -ge 400) { $result.Outcome = 'HttpError' }
                }
            }
        }
    } catch {
        $result.Outcome = $(if ($_.Exception -is [TimeoutException]) { 'TimedOut' } else { 'Failed' })
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
    [pscustomobject]@{ Name = $Name; FunctionName = 'Invoke-ConnectivityProbe'; Arguments = $Arguments; TimeoutSeconds = $TimeoutSeconds }
}

function Get-ConnectivityDefinitions {
    param([object[]]$Checks, [string[]]$TcpDestinations, [int]$TcpPort, [string]$DnsQueryName,
        [string]$HttpsEndpoint, [int]$ProbeTimeoutSeconds, [bool]$IncludeGatewayPing)
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
    $dns = @($Checks | Where-Object { $_.Name -eq 'DNSServers' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    foreach ($server in @($dns | ForEach-Object {
        $entry = $_
        foreach ($address in $entry.ServerAddresses) {
            $value = [string]$address
            if ($value -like 'fe80:*' -and $value -notlike '*%*') { $value += '%' + $entry.InterfaceIndex }
            $value
        }
    } | Select-Object -Unique)) {
        foreach ($type in @('A','AAAA')) {
            New-ProbeDefinition "Connectivity:DNS:${server}:$type" @{ Kind = 'DNS'; Destination = $server; QueryName = $DnsQueryName; QueryType = $type; TimeoutMs = $commonMs } $ProbeTimeoutSeconds
        }
    }
    foreach ($destination in @($TcpDestinations | Select-Object -Unique)) {
        New-ProbeDefinition "Connectivity:Resolve:TCP:$destination" @{ Kind = 'Resolve'; Destination = $destination } $ProbeTimeoutSeconds
    }
    New-ProbeDefinition 'Connectivity:Resolve:HTTPS' @{ Kind = 'Resolve'; Destination = ([uri]$HttpsEndpoint).DnsSafeHost } $ProbeTimeoutSeconds
}
