function Get-DnsTargetInventory {
    param([object[]]$Checks, [bool]$IncludeLegacyDnsTargets = $false)
    $dns = @($Checks | Where-Object { $_.Name -eq 'DNSServers' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    $adapters = @($Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    $interfaces = @($Checks | Where-Object { $_.Name -eq 'InterfacesAndMetrics' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    $targets = [ordered]@{}
    foreach ($entry in $dns) {
        foreach ($original in $entry.ServerAddresses) {
            $original = [string]$original
            $parts = $original.Split('%')
            $ip = $null
            $valid = [Net.IPAddress]::TryParse($parts[0], [ref]$ip)
            $v6 = $valid -and $ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
            $scope = $(if ($parts.Count -gt 1) { $parts[1] } else { $null })
            $normal = $(if ($valid) { $ip.ToString() } else { $original })
            $legacy = $false
            if ($v6) {
                foreach ($n in 1..3) { if ($ip.Equals([Net.IPAddress]::Parse("fec0:0:0:ffff::$n"))) { $legacy = $true } }
            }
            $uncertainty = @()
            $key = $normal
            if ($parts.Count -gt 1) {
                $zone = 0L
                if ([long]::TryParse($scope, [ref]$zone) -and $zone -ge 0 -and $parts.Count -eq 2 -and $v6) {
                    $normal += '%' + $zone
                    $key = $normal
                    if ($zone -eq 0) { $uncertainty += 'Explicit zero scope does not establish a zone.' }
                    elseif ($zone -ne $entry.InterfaceIndex) { $uncertainty += 'Explicit zone differs from configured interface index; original zone retained, query path unconfirmed.' }
                } else {
                    $normal = $original
                    $key = $original
                    $uncertainty += 'Scope suffix could not be established as a numeric IPv6 zone; original target retained.'
                }
            } elseif ($v6 -and ($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal)) {
                # Do not invent a zone from the configured interface. Keep ambiguous entries separate.
                if (-not $legacy) { $key += '|unscoped-interface:' + $entry.InterfaceIndex }
                $uncertainty += 'Scoped IPv6 address has no explicit zone; configured interface is not an observed query path.'
            }
            $family = $(if ($v6) { 'IPv6' } elseif ($valid) { 'IPv4' } else { 'Unknown' })
            $matching = @($adapters | Where-Object InterfaceIndex -eq $entry.InterfaceIndex)
            $states = @($interfaces | Where-Object { $_.InterfaceIndex -eq $entry.InterfaceIndex -and
                (($v6 -and [string]$_.AddressFamily -in @('23','IPv6','InterNetworkV6')) -or
                (-not $v6 -and [string]$_.AddressFamily -in @('2','IPv4','InterNetwork'))) } |
                Select-Object InterfaceAlias,AddressFamily,ConnectionState)
            $association = [pscustomobject]@{ OriginalAddress = $original; ScopeId = $scope
                InterfaceIndex = $entry.InterfaceIndex; InterfaceAlias = $entry.InterfaceAlias
                Adapters = @($matching | Select-Object Name,Status,@{n='Kind';e={ if ($null -eq $_.HardwareInterface) { 'Unknown' } elseif ($_.HardwareInterface) { 'Physical' } else { 'Virtual/software' } }})
                IPInterfaceStates = $states }
            if (-not $targets.Contains($key)) {
                $reason = $(if ($legacy) { 'Legacy DNS discovery address; operational use unconfirmed.' } else { 'Configured DNS server; operational use and query interface unconfirmed.' })
                $targets[$key] = [pscustomobject]@{ TargetId = $key; Server = $normal; NormalizedAddress = $normal
                    OriginalAddresses = @(); ScopeId = $scope; AddressFamily = $family
                    Classification = $(if ($legacy) { 'LegacyDiscovery' } else { 'Configured' })
                    Selection = $(if ($legacy -and -not $IncludeLegacyDnsTargets) { 'Skipped' } else { 'Selected' })
                    Reason = $reason; ScopeUncertainty = @(); ConfiguredAssociations = @()
                    Attribution = 'Configured associations only; not proof of query source interface.' }
            }
            $target = $targets[$key]
            $target.OriginalAddresses = @(@($target.OriginalAddresses) + @($original) | Select-Object -Unique)
            $target.ConfiguredAssociations += $association
            $target.ScopeUncertainty = @(@($target.ScopeUncertainty) + $uncertainty | Select-Object -Unique)
        }
    }
    $targets.Values
}

function Get-DnsErrorDetail {
    param([Management.Automation.ErrorRecord]$Record)
    $codes = @()
    $exception = $Record.Exception
    while ($null -ne $exception) {
        foreach ($name in @('NativeErrorCode','ErrorCode','HResult')) {
            $property = $exception.PSObject.Properties[$name]
            $number = 0L
            if ($null -ne $property -and [long]::TryParse([string]$property.Value, [ref]$number)) {
                $codes += [pscustomobject]@{ Source = $name; Value = $number; ExceptionType = $exception.GetType().FullName }
                # HRESULT_FROM_WIN32 only; never interpret an arbitrary HRESULT's low bits.
                if (($number -band 4294901760L) -eq 2147942400L) {
                    $codes += [pscustomobject]@{ Source = 'Win32FromHResult'; Value = ($number -band 65535); ExceptionType = $exception.GetType().FullName }
                }
            }
        }
        $exception = $exception.InnerException
    }
    $map = @{ 1460 = 'Timeout'; 10060 = 'Timeout'; 9003 = 'NameError/NXDOMAIN'; 9002 = 'ServerFailure'; 9005 = 'Refused' }
    $known = @($codes | Where-Object { $_.Source -in @('NativeErrorCode','Win32FromHResult') -and $_.Value -ge 0 -and $_.Value -le 2147483647 -and $map.ContainsKey([int]$_.Value) })
    $classifications = @($known | ForEach-Object { $map[[int]$_.Value] } | Select-Object -Unique)
    $classification = $(if ($classifications.Count -eq 1) { $classifications[0] } else { 'Unknown' })
    [pscustomobject]@{ Classification = $classification; Code = $(if ($classifications.Count -eq 1) { $known[0].Value } else { $null })
        NumericCodes = $codes; Message = $Record.Exception.Message; FullyQualifiedErrorId = $Record.FullyQualifiedErrorId
        Category = [string]$Record.CategoryInfo.Category; ExceptionType = $Record.Exception.GetType().FullName }
}
