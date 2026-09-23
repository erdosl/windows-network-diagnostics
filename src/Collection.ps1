function Get-RecentNetworkEvents {
    param([string]$LogName, [datetime]$StartTime, [datetime]$EndTime, [int]$MaxEvents, [string[]]$Providers)
    $log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
    if (-not $log.IsEnabled) { throw [NotSupportedException]::new("Event log is disabled: $LogName") }
    $filter = @{ LogName = $LogName; StartTime = $StartTime; EndTime = $EndTime }
    if ($Providers.Count -gt 0) { $filter.ProviderName = $Providers }
    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -match '^NoMatchingEventsFound') { $events = @() }
        else { throw }
    }
    [pscustomobject]@{
        LogName = $LogName; StartTime = $StartTime.ToString('o'); EndTime = $EndTime.ToString('o')
        MaxEvents = $MaxEvents; LimitReached = ($events.Count -eq $MaxEvents)
        Events = @($events | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, RecordId, Message)
    }
}

function Get-NetworkSnapshot {
    param([ValidateRange(1,168)][int]$LookbackHours = 24, [ValidateRange(1,1000)][int]$MaxEventsPerLog = 200)
    $now = [DateTimeOffset]::Now
    $checks = @()
    $checks += Invoke-DiagnosticCheck 'Windows' {
        Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
    }
    $checks += Invoke-DiagnosticCheck 'TimeZone' {
        $zone = [TimeZoneInfo]::Local
        [pscustomobject]@{ Id = $zone.Id; DisplayName = $zone.DisplayName; UtcOffset = $now.Offset.ToString(); Timestamp = $now.ToString('o') }
    }
    $checks += Invoke-DiagnosticCheck 'Adapters' {
        Get-NetAdapter -IncludeHidden -ErrorAction Stop | Select-Object Name, InterfaceDescription, InterfaceIndex, InterfaceGuid,
            MacAddress, Status, LinkSpeed, InterfaceType, HardwareInterface, MediaType, PhysicalMediaType,
            DriverInformation, DriverFileName, DriverVersion, DriverDate, PnPDeviceID
    }
    $checks += Invoke-DiagnosticCheck 'NICDrivers' {
        Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass = 'NET'" -ErrorAction Stop |
            Select-Object DeviceName, DeviceID, DriverVersion, DriverDate, DriverProviderName, InfName, IsSigned
    }
    $checks += Invoke-DiagnosticCheck 'IPAddresses' {
        Get-NetIPAddress -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, IPAddress, PrefixLength,
            AddressFamily, PrefixOrigin, SuffixOrigin, AddressState, ValidLifetime, PreferredLifetime, SkipAsSource
    }
    $checks += Invoke-DiagnosticCheck 'DHCPAndGateways' {
        Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction Stop | Select-Object InterfaceIndex, Index, Description,
            SettingID, IPEnabled, DHCPEnabled, DHCPServer, DHCPLeaseObtained, DHCPLeaseExpires,
            IPAddress, IPSubnet, DefaultIPGateway, GatewayCostMetric, DNSServerSearchOrder, DNSDomain, DNSDomainSuffixSearchOrder
    }
    $checks += Invoke-DiagnosticCheck 'DNSServers' {
        Get-DnsClientServerAddress -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, ServerAddresses
    }
    $checks += Invoke-DiagnosticCheck 'InterfacesAndMetrics' {
        Get-NetIPInterface -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, ConnectionState,
            Dhcp, AutomaticMetric, InterfaceMetric, NlMtu, RouterDiscovery
    }
    $checks += Invoke-DiagnosticCheck 'Routes' {
        Get-NetRoute -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, DestinationPrefix,
            NextHop, RouteMetric, InterfaceMetric, Protocol, State, PolicyStore
    }
    $checks += Invoke-DiagnosticCheck 'Neighbours' {
        Get-NetNeighbor -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, IPAddress, LinkLayerAddress, State
    }
    $checks += Invoke-DiagnosticCheck 'WiFiConnection' {
        # Connection state only: no profiles or key export. Preserve localized native output.
        $lines = & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1
        if ($LASTEXITCODE -ne 0) { throw "netsh wlan show interfaces exited with code ${LASTEXITCODE}: $($lines -join [Environment]::NewLine)" }
        [pscustomobject]@{ Command = 'netsh wlan show interfaces'; Text = $lines -join [Environment]::NewLine }
    }
    $eventEnd = $now.LocalDateTime
    $eventStart = $eventEnd.AddHours(-$LookbackHours)
    $checks += Invoke-DiagnosticCheck 'Events:System' {
        Get-RecentNetworkEvents -LogName 'System' -StartTime $eventStart -EndTime $eventEnd -MaxEvents $MaxEventsPerLog -Providers @(
            'Microsoft-Windows-Dhcp-Client', 'Microsoft-Windows-TCPIP', 'Tcpip', 'Microsoft-Windows-NDIS',
            'Microsoft-Windows-DNS-Client', 'Microsoft-Windows-Kernel-PnP')
    }
    foreach ($logName in @('Microsoft-Windows-Dhcp-Client/Admin', 'Microsoft-Windows-Dhcp-Client/Operational',
        'Microsoft-Windows-WLAN-AutoConfig/Operational', 'Microsoft-Windows-Wired-AutoConfig/Operational')) {
        $checks += Invoke-DiagnosticCheck "Events:$logName" {
            Get-RecentNetworkEvents -LogName $logName -StartTime $eventStart -EndTime $eventEnd -MaxEvents $MaxEventsPerLog -Providers @()
        }
    }
    [pscustomobject]@{
        SchemaVersion = 1; Mode = 'Snapshot'; CollectedAt = $now.ToString('o'); CompletedAt = [DateTimeOffset]::Now.ToString('o')
        PowerShellVersion = $PSVersionTable.PSVersion.ToString(); LookbackHours = $LookbackHours; MaxEventsPerLog = $MaxEventsPerLog
        Checks = $checks; Findings = Get-DiagnosticFindings -Checks $checks
    }
}
