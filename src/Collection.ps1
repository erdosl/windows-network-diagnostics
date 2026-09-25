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
        # Unfiltered inventory: do not route this through literal-name detail
        # selection, filter by state, or collapse similar installation identities.
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
        Get-WifiConnectionEvidence
        }
        'NICServices' {
            Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
                Select-Object InterfaceIndex, Name, ServiceName, PNPDeviceID
        }
        default { throw "Unknown passive collector: $Name" }
    }
}

function Invoke-WlanCommand {
    # No profile/key export; retain the original native response, including stderr.
    $ErrorActionPreference='Continue'
    $lines=@(& "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1)
    [pscustomobject]@{Command='netsh wlan show interfaces';ExitCode=$LASTEXITCODE;Text=($lines | ForEach-Object {[string]$_}) -join [Environment]::NewLine}
}

function Get-WifiConnectionEvidence {
    $service=Invoke-DiagnosticCheck 'WlanService' {Get-CimInstance Win32_Service -Filter "Name='wlansvc'" -ErrorAction Stop | Select-Object Name,State,Started}
    $inventory=Invoke-DiagnosticCheck 'WlanAdapterInventory' {Get-NetAdapter -IncludeHidden -ErrorAction Stop | Select-Object Name,InterfaceGuid,InterfaceIndex,InterfaceType,PhysicalMediaType}
    $command=Invoke-WlanCommand
    $reason=$null
    if($service.Status -eq 'Success'){
        if($service.Data.Count -eq 0){$reason='WlanServiceAbsent'}
        elseif($service.Data.Count -eq 1 -and $service.Data[0].State -eq 'Stopped'){$reason='WlanServiceStopped'}
    }
    if(-not $reason -and $inventory.Status -eq 'Success' -and
        @($inventory.Data | Where-Object {[string]$_.InterfaceType -notin @('6','23','24','71','131','Ethernet','Ppp','SoftwareLoopback','IEEE80211','Tunnel')}).Count -eq 0 -and
        @($inventory.Data | Where-Object {[string]$_.InterfaceType -in @('71','IEEE80211') -or [string]$_.PhysicalMediaType -in @('1','9','WirelessLan','Native802_11')}).Count -eq 0){$reason='NoWifiAdapterInCompleteInventory'}
    $evidence=[pscustomobject]@{ContractVersion=1;Reason=$reason;Command=$command;Service=$service;AdapterInventory=$inventory}
    if($command.ExitCode -ne 0 -or $reason){
        $failure=[InvalidOperationException]::new("Wi-Fi connection evidence unavailable or failed; native exit code $($command.ExitCode).")
        $failure.Data['Evidence']=$evidence
        $failure.Data['EvidenceStatus']='Failed'
        if($reason -and $command.ExitCode -in @(0,1)){$failure.Data['EvidenceStatus']='Unavailable'}
        if($command.ExitCode -eq 5){$failure.Data['EvidenceStatus']='PermissionDenied';$evidence.Reason='NativeAccessDenied'}
        throw $failure
    }
    $evidence
}

function Invoke-AdapterDetail {
    param([ValidateSet('AdapterStatistics','AdapterPowerManagement')][string]$Kind,
        [string]$AdapterName,[int]$InterfaceIndex,[string]$InterfaceGuid,
        [AllowEmptyCollection()][object[]]$ProviderInventory,
        [string]$InterfaceDescription,[object[]]$AdapterInventory)
    $ErrorActionPreference='Stop'
    $started=[DateTimeOffset]::Now.ToString('o')
    $diagnostic=[pscustomobject]@{ContractVersion=1;QueryScope='LiteralAdapterName';QueryStatus='NotCompleted';Outcome='QueryFailed';RowCount=$null;Rows=@();MatchBasis=$null;NativeException=$true}
    try {
        # CDXML RegularQuery supports globbing; escape before querying, then verify
        # returned identities. No fallback to global power-provider enumeration.
        if(-not $PSBoundParameters.ContainsKey('ProviderInventory') -and [string]::IsNullOrWhiteSpace($AdapterName)){
            $diagnostic.NativeException=$false;$diagnostic.Outcome='MissingTargetIdentity'
            throw [InvalidOperationException]::new('Literal adapter name is missing; provider query not attempted.')
        }
        $literal=[Management.Automation.WildcardPattern]::Escape($AdapterName)
        if ($PSBoundParameters.ContainsKey('ProviderInventory')) { $inventory=@($ProviderInventory);$diagnostic.QueryScope='BatchEnumeration' }
        elseif ($Kind -eq 'AdapterStatistics') { $inventory=@(Get-NetAdapterStatistics -Name $literal -IncludeHidden -ErrorAction Stop) }
        else { $inventory=@(Get-NetAdapterPowerManagement -Name $literal -IncludeHidden -ErrorAction Stop) }
        $diagnostic.QueryStatus='Success';$diagnostic.RowCount=$inventory.Count;$diagnostic.NativeException=$false
        $diagnostic.Rows=@($inventory | ForEach-Object {
            [pscustomobject]@{Name=$_.Name;InterfaceDescription=$_.InterfaceDescription;InterfaceGuid=$_.InterfaceGuid;InterfaceIndex=$_.InterfaceIndex;InstanceID=$_.InstanceID;PropertyNames=@($_.PSObject.Properties.Name)}
        })
        $target=[pscustomobject]@{Name=$AdapterName;InterfaceDescription=$InterfaceDescription;InterfaceGuid=$InterfaceGuid;InterfaceIndex=$InterfaceIndex}
        $records=@();$bases=@();$conflict=$false
        foreach($row in $inventory){
            # InstanceID is an opaque provider key, not an assumed adapter GUID.
            # InterfaceDescription is the exact installation identity, never fuzzy text.
            $basis=$null
            foreach($field in @('InterfaceGuid','InterfaceDescription','Name')){
                $a=[string]$target.$field;$b=[string]$row.$field
                if($field -eq 'InterfaceGuid'){$a=$a.Trim('{}');$b=$b.Trim('{}')}
                if($a -and $b -and [string]::Equals($a,$b,[StringComparison]::OrdinalIgnoreCase)){$basis=$field;break}
            }
            if(-not $basis){continue}
            foreach($field in @('InterfaceGuid','InterfaceIndex','InterfaceDescription')){
                $a=[string]$target.$field;$b=[string]$row.$field
                if($field -eq 'InterfaceGuid'){$a=$a.Trim('{}');$b=$b.Trim('{}')}
                if($a -and $b -and $a -ne $b){$conflict=$true}
            }
            # A changed alias is allowed only if it does not identify another inventory row.
            if($AdapterInventory){
                foreach($field in @('InterfaceGuid','InterfaceDescription','Name')){
                    if(-not $row.$field){continue}
                    $owners=@($AdapterInventory | Where-Object {([string]$_.$field).Trim('{}') -eq ([string]$row.$field).Trim('{}')})
                    if($owners.Count -gt 1 -or ($owners.Count -eq 1 -and $owners[0].InterfaceIndex -ne $InterfaceIndex)){$conflict=$true}
                }
            }
            $records+=$row;$bases+=$basis
        }
        if($conflict -or $records.Count -gt 1){
            $diagnostic.Outcome=$(if($conflict){'IdentityConflict'}else{'Ambiguous'})
            throw [InvalidOperationException]::new('Ambiguous or conflicting adapter-provider identity; no attribution made.')
        }
        if (-not $records.Count) {
            $diagnostic.Outcome=$(if($inventory.Count){'PresentUnmatched'}else{'ProviderRowsAbsent'})
            $missing=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('No matching adapter-provider object was returned.'),'AdapterProviderObjectMissing',[Management.Automation.ErrorCategory]::ObjectNotFound,$AdapterName)
            throw $missing
        }
        $diagnostic.Outcome='Matched';$diagnostic.MatchBasis=$bases[0]
    } catch {
        if($diagnostic.NativeException){$diagnostic.QueryStatus='Failed'}
        $_.Exception.Data['AdapterProviderContext']=$Kind
        $_.Exception.Data['ProviderDiagnostic']=$diagnostic
        $_.Exception.Data['AdapterIdentity']=[pscustomobject]@{Name=$AdapterName;InterfaceIndex=$InterfaceIndex;InterfaceGuid=$InterfaceGuid;InterfaceDescription=$InterfaceDescription;IncludeHidden=$true;Selection=$diagnostic.QueryScope}
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
        [pscustomobject]@{AdapterName=$AdapterName;InterfaceIndex=$InterfaceIndex;InterfaceGuid=$InterfaceGuid;StartedAt=$started;CompletedAt=[DateTimeOffset]::Now.ToString('o');Fields=[pscustomobject]$fields;ProviderDiagnostic=$diagnostic
            Limitation=$(if($Kind -eq 'AdapterStatistics'){'Single cumulative counter sample, not a rate or proof of a current fault.'}else{'Reported power-management capabilities/settings only; no changes made.'})}
    }
}

# Observation-only batch: one enumeration, preserving independent attribution.
function Invoke-ObservationStatistics {
    param([object[]]$Adapters,$TimingContext)
    $collectedAt=[DateTimeOffset]::Now.ToString('o')
    $queryTicks=[Diagnostics.Stopwatch]::GetTimestamp()
    # '*' is intentionally the entire batch, never an escaped literal target.
    # Stop also promotes nonterminating provider errors; empty success must not
    # represent a suppressed native error.
    try{$inventory=@(Get-NetAdapterStatistics -Name '*' -IncludeHidden -ErrorAction Stop)}
    catch{
        $_.Exception.Data['AdapterProviderContext']='AdapterStatistics'
        $_.Exception.Data['ProviderDiagnostic']=[pscustomobject]@{ContractVersion=1;QueryScope='BatchEnumeration';QueryStatus='Failed';Outcome='QueryFailed';RowCount=$null;NativeException=$true;AffectedAdapters=@($Adapters | Select-Object Name,InterfaceIndex,InterfaceGuid)}
        throw
    }
    $completedAt=[DateTimeOffset]::Now.ToString('o')
    $queryEndTicks=[Diagnostics.Stopwatch]::GetTimestamp()
    foreach($adapter in $Adapters){
        $result=Invoke-DiagnosticCheck ('AdapterStatistics:'+$adapter.InterfaceIndex) {
            if(@($Adapters | Where-Object Name -eq $adapter.Name).Count -ne 1 -or
                ($adapter.InterfaceGuid -and @($Adapters | Where-Object InterfaceGuid -eq $adapter.InterfaceGuid).Count -gt 1)){
                $failure=[InvalidOperationException]::new('Ambiguous adapter-provider mapping; no attribution made.')
                $failure.Data['AdapterProviderContext']='AdapterStatistics'
                $failure.Data['ProviderDiagnostic']=[pscustomobject]@{ContractVersion=1;QueryScope='BatchEnumeration';QueryStatus='Success';Outcome='AmbiguousInventory';RowCount=$inventory.Count;NativeException=$false}
                throw $failure
            }
            Invoke-AdapterDetail -Kind AdapterStatistics -AdapterName $adapter.Name -InterfaceIndex $adapter.InterfaceIndex -InterfaceGuid $adapter.InterfaceGuid -InterfaceDescription $adapter.InterfaceDescription -AdapterInventory $Adapters -ProviderInventory $inventory
        }
        $result | Add-Member NoteProperty AdapterIdentity ($adapter | Select-Object Name,InterfaceIndex,InterfaceGuid)
        foreach($row in $result.Data){
            $row.StartedAt=$collectedAt;$row.CompletedAt=$completedAt
            if($TimingContext -and $TimingContext.Frequency -eq [Diagnostics.Stopwatch]::Frequency){
                $row | Add-Member NoteProperty CounterTiming ([pscustomobject]@{ContractVersion=1;RunId=$TimingContext.RunId;Basis='SystemStopwatch';StartSeconds=($queryTicks-$TimingContext.OriginTicks)/[double]$TimingContext.Frequency;EndSeconds=($queryEndTicks-$TimingContext.OriginTicks)/[double]$TimingContext.Frequency})
            }
        }
        $result
    }
}
