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

function Invoke-AdapterDetail {
    param([ValidateSet('AdapterStatistics','AdapterPowerManagement')][string]$Kind,
        [string]$AdapterName,[int]$InterfaceIndex,[string]$InterfaceGuid,
        [AllowEmptyCollection()][object[]]$ProviderInventory)
    $ErrorActionPreference='Stop'
    $started=[DateTimeOffset]::Now.ToString('o')
    try {
        # The provider Name parameter accepts patterns. Enumerate hidden objects too,
        # then compare literal names locally; brackets/*/? in aliases cannot broaden a query.
        if ($PSBoundParameters.ContainsKey('ProviderInventory')) { $inventory=@($ProviderInventory) }
        elseif ($Kind -eq 'AdapterStatistics') { $inventory=@(Get-NetAdapterStatistics -Name '*' -IncludeHidden -ErrorAction Stop) }
        else { $inventory=@(Get-NetAdapterPowerManagement -Name '*' -IncludeHidden -ErrorAction Stop) }
        $records=@($inventory | Where-Object { [string]::Equals([string]$_.Name,$AdapterName,[StringComparison]::OrdinalIgnoreCase) })
        if (-not $records.Count) {
            $missing=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('No matching adapter-provider object was returned.'),'AdapterProviderObjectMissing',[Management.Automation.ErrorCategory]::ObjectNotFound,$AdapterName)
            throw $missing
        }
        foreach ($record in $records) {
            if (($null -ne $record.InterfaceIndex -and [int]$record.InterfaceIndex -ne $InterfaceIndex) -or
                ($InterfaceGuid -and $record.InterfaceGuid -and ([string]$record.InterfaceGuid).Trim('{}') -ne $InterfaceGuid.Trim('{}'))) {
                throw [InvalidOperationException]::new('Adapter-provider identity differs from snapshot inventory; no attribution made.')
            }
        }
    } catch {
        $_.Exception.Data['AdapterProviderContext']=$Kind
        $_.Exception.Data['AdapterIdentity']=[pscustomobject]@{Name=$AdapterName;InterfaceIndex=$InterfaceIndex;InterfaceGuid=$InterfaceGuid;IncludeHidden=$true;Selection='OrdinalIgnoreCase literal name after provider inventory enumeration'}
        $expected=$(if($Kind -eq 'AdapterStatistics'){'Get-NetAdapterStatistics'}else{'Get-NetAdapterPowerManagement'})
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound' -and
            ($_.FullyQualifiedErrorId -eq 'AdapterProviderObjectMissing' -or $_.FullyQualifiedErrorId -eq ('CmdletizationQuery_NotFound_Name,'+$expected))) {
            $_.Exception.Data['AdapterProviderMissing']=$true
        }
        throw
    }
    foreach ($record in $records) {
        $fields=[ordered]@{}
        # Retain supported provider properties, excluding transport/CIM bookkeeping.
        foreach ($property in $record.PSObject.Properties) {
            if ($property.Name -notmatch '^(Cim|PS|RunspaceId)' -and $property.MemberType -in @('Property','NoteProperty','AliasProperty')) { $fields[$property.Name]=$property.Value }
        }
        [pscustomobject]@{AdapterName=$AdapterName;InterfaceIndex=$InterfaceIndex;InterfaceGuid=$InterfaceGuid;StartedAt=$started;CompletedAt=[DateTimeOffset]::Now.ToString('o');Fields=[pscustomobject]$fields
            Limitation=$(if($Kind -eq 'AdapterStatistics'){'Single cumulative counter sample, not a rate or proof of a current fault.'}else{'Reported power-management capabilities/settings only; no changes made.'})}
    }
}

# Observation-only batch. Snapshot callers continue to enumerate independently.
function Invoke-ObservationStatistics {
    param([object[]]$Adapters)
    $collectedAt=[DateTimeOffset]::Now.ToString('o')
    $inventory=@(Get-NetAdapterStatistics -Name '*' -IncludeHidden -ErrorAction Stop)
    $completedAt=[DateTimeOffset]::Now.ToString('o')
    foreach($adapter in $Adapters){
        $result=Invoke-DiagnosticCheck ('AdapterStatistics:'+$adapter.InterfaceIndex) {
            $rows=@($inventory | Where-Object {[string]::Equals([string]$_.Name,[string]$adapter.Name,[StringComparison]::OrdinalIgnoreCase)})
            if($rows.Count -gt 1 -or @($Adapters | Where-Object Name -eq $adapter.Name).Count -ne 1 -or
                ($adapter.InterfaceGuid -and @($Adapters | Where-Object InterfaceGuid -eq $adapter.InterfaceGuid).Count -gt 1)){
                throw [InvalidOperationException]::new('Ambiguous adapter-provider mapping; no attribution made.')
            }
            Invoke-AdapterDetail -Kind AdapterStatistics -AdapterName $adapter.Name -InterfaceIndex $adapter.InterfaceIndex -InterfaceGuid $adapter.InterfaceGuid -ProviderInventory $inventory
        }
        $result | Add-Member NoteProperty AdapterIdentity ($adapter | Select-Object Name,InterfaceIndex,InterfaceGuid)
        foreach($row in $result.Data){$row.StartedAt=$collectedAt;$row.CompletedAt=$completedAt}
        $result
    }
}
