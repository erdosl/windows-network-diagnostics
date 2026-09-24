function Set-AtomicText {
    param([string]$Path, [string]$Text)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        # Indexers and sync clients can briefly open a destination without delete
        # sharing. Retry the atomic operation; never fall back to delete-then-move.
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, ($Path + '.bak')) }
                else { [IO.File]::Move($temporary, $Path) }
                break
            } catch {
                if ($attempt -eq 9 -or -not [IO.File]::Exists($temporary)) { throw }
                Start-Sleep -Milliseconds 200
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-DiagnosticEvidence {
    param([Parameter(Mandatory)][string]$Path)
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        $recovered = Get-Content -LiteralPath ($Path + '.bak') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $recovered.CollectionStatus = 'Incomplete'
        $recovered.CompletedAt = $null
        $recovered | Add-Member -NotePropertyName RecoveryNote -NotePropertyValue 'Recovered previous checkpoint; latest revision could not be read.' -Force
        return $recovered
    }
}

function New-SnapshotIdentity {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    [pscustomobject]@{ ComputerName = [Environment]::MachineName; RunId = [guid]::NewGuid().ToString('D')
        CollectorVersion = '0.4.1'; IsElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        StartedAt = [DateTimeOffset]::Now.ToString('o') }
}

function Get-InterfaceSummary {
    param([object[]]$Checks)
    $names = @('Adapters','IPAddresses','DHCPAndGateways','DNSServers','Routes','InterfacesAndMetrics')
    $data = @{}
    $states = [ordered]@{}
    foreach ($name in $names) {
        $check = @($Checks | Where-Object Name -eq $name | Select-Object -Last 1)
        $states[$name] = $(if ($check.Count -eq 0) { 'NotCollected' } else { $check[0].Status })
        $data[$name] = @($check | Where-Object Status -eq 'Success' | ForEach-Object { $_.Data })
    }
    $indices = @($names | ForEach-Object { $data[$_] } | Where-Object { $null -ne $_.InterfaceIndex } |
        ForEach-Object { $_.InterfaceIndex } | Sort-Object -Unique)
    foreach ($index in $indices) {
        $adapters = @($data.Adapters | Where-Object InterfaceIndex -eq $index | Select-Object Name,InterfaceIndex,InterfaceDescription,
            @{n='Kind';e={ if ($null -eq $_.HardwareInterface) { 'Unknown' } elseif ($_.HardwareInterface) { 'Physical' } else { 'Virtual/software' } }},
            Status,LinkSpeed,MacAddress)
        $metrics = @($data.InterfacesAndMetrics | Where-Object InterfaceIndex -eq $index)
        $routes = @($data.Routes | Where-Object { $_.InterfaceIndex -eq $index -and $_.DestinationPrefix -in @('0.0.0.0/0','::/0') } |
            ForEach-Object {
                $route = $_
                [pscustomobject]@{ DestinationPrefix = $route.DestinationPrefix; NextHop = $route.NextHop; AddressFamily = $route.AddressFamily
                    RouteMetric = $route.RouteMetric; RouteReportedInterfaceMetric = $route.InterfaceMetric
                    InterfaceMetrics = @($metrics | Where-Object AddressFamily -eq $route.AddressFamily | Select-Object AddressFamily,InterfaceMetric,AutomaticMetric) }
            })
        [pscustomobject]@{ InterfaceIndex = $index; Adapters = $adapters
            Addresses = @($data.IPAddresses | Where-Object InterfaceIndex -eq $index | Select-Object IPAddress,PrefixLength,AddressFamily,AddressState)
            DHCP = @($data.DHCPAndGateways | Where-Object InterfaceIndex -eq $index | Select-Object DHCPEnabled,DHCPServer,DHCPLeaseObtained,DHCPLeaseExpires)
            DefaultRoutes = $routes; InterfaceMetrics = $metrics
            DNS = @($data.DNSServers | Where-Object InterfaceIndex -eq $index | Select-Object AddressFamily,ServerAddresses)
            SourceStatus = [pscustomobject]$states }
    }
}
