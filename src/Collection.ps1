function Invoke-SnapshotCollector {
    param([Parameter(Mandatory)][string]$Name)
    $ErrorActionPreference = 'Stop'
    $now = [DateTimeOffset]::Now
    switch ($Name) {
        'Windows' {
        Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime
        }
        'TimeZone' {
        $zone = [TimeZoneInfo]::Local
        [pscustomobject]@{ Id = $zone.Id; DisplayName = $zone.DisplayName; UtcOffset = $now.Offset.ToString(); Timestamp = $now.ToString('o') }
        }
        'Adapters' {
        Get-NetAdapter -IncludeHidden -ErrorAction Stop | Select-Object Name, InterfaceDescription, InterfaceIndex, InterfaceGuid,
            MacAddress, Status, LinkSpeed, InterfaceType, HardwareInterface, MediaType, PhysicalMediaType,
            DriverInformation, DriverFileName, DriverVersion, DriverDate, PnPDeviceID
        }
        'NICDrivers' {
        Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass = 'NET'" -ErrorAction Stop |
            Select-Object DeviceName, DeviceID, DriverVersion, DriverDate, DriverProviderName, InfName, IsSigned
        }
        'IPAddresses' {
        Get-NetIPAddress -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, IPAddress, PrefixLength,
            AddressFamily, PrefixOrigin, SuffixOrigin, AddressState, ValidLifetime, PreferredLifetime, SkipAsSource
        }
        'DHCPAndGateways' {
        Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction Stop | Select-Object InterfaceIndex, Index, Description,
            SettingID, IPEnabled, DHCPEnabled, DHCPServer, DHCPLeaseObtained, DHCPLeaseExpires,
            IPAddress, IPSubnet, DefaultIPGateway, GatewayCostMetric, DNSServerSearchOrder, DNSDomain, DNSDomainSuffixSearchOrder
        }
        'DNSServers' {
        Get-DnsClientServerAddress -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, ServerAddresses
        }
        'InterfacesAndMetrics' {
        Get-NetIPInterface -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, ConnectionState,
            Dhcp, AutomaticMetric, InterfaceMetric, NlMtu, RouterDiscovery
        }
        'Routes' {
        Get-NetRoute -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, DestinationPrefix,
            NextHop, RouteMetric, InterfaceMetric, Protocol, State, PolicyStore
        }
        'Neighbours' {
        Get-NetNeighbor -ErrorAction Stop | Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, IPAddress, LinkLayerAddress, State
        }
        'WiFiConnection' {
        # Connection state only: no profiles or key export. Preserve localized native output.
        $lines = & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1
        if ($LASTEXITCODE -ne 0) { throw "netsh wlan show interfaces exited with code ${LASTEXITCODE}: $($lines -join [Environment]::NewLine)" }
        [pscustomobject]@{ Command = 'netsh wlan show interfaces'; Text = $lines -join [Environment]::NewLine }
        }
        'NICServices' {
            Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
                Select-Object InterfaceIndex, Name, ServiceName, PNPDeviceID
        }
        default { throw "Unknown passive collector: $Name" }
    }
}