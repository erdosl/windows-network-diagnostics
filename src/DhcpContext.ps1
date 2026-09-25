function Compare-LeaseTimestamp {
    param($Before,$After,[string]$BeforeState='Value',[string]$AfterState='Value')
    $left=ConvertTo-ContextTime $Before;$right=ConvertTo-ContextTime $After
    $classification='Unassessed';$outcome='Not assessed'
    if($BeforeState -eq 'Value' -and $null -eq $Before){$BeforeState='ObservedNull'}
    if($AfterState -eq 'Value' -and $null -eq $After){$AfterState='ObservedNull'}
    if($BeforeState -eq 'Value' -and (($Before -is [string] -and $Before -eq '') -or ($Before -is [array] -and $Before.Count -eq 0))){$BeforeState='ObservedEmpty'}
    if($AfterState -eq 'Value' -and (($After -is [string] -and $After -eq '') -or ($After -is [array] -and $After.Count -eq 0))){$AfterState='ObservedEmpty'}
    if($BeforeState -notin @('MissingProperty','Unavailable') -and $AfterState -notin @('MissingProperty','Unavailable')){
        if($null -eq $Before -and $null -eq $After){$classification='ObservedNullUnchanged';$outcome='Unchanged'}
        elseif($Before -is [string] -and $After -is [string] -and $Before -eq '' -and $After -eq ''){$classification='ObservedEmptyUnchanged';$outcome='Unchanged'}
        elseif($left -and $right){
            if($right -eq $left){$classification='SameInstant';$outcome='Unchanged'}
            elseif($right -gt $left){$classification='ForwardProgression';$outcome='LeaseRefreshed'}
            else{$classification='BackwardMovement';$outcome='Changed'}
        } elseif($left -and ($null -eq $After -or [string]$After -eq '')){$classification='Cleared';$outcome='Changed'}
        elseif($right -and ($null -eq $Before -or [string]$Before -eq '')){$classification='BecameAvailable';$outcome='Changed'}
        elseif(($null -ne $Before -and [string]$Before -ne '' -and -not $left) -or ($null -ne $After -and [string]$After -ne '' -and -not $right)){$classification='InvalidTimestamp'}
    }
    [pscustomobject]@{ContractVersion=1;Outcome=$outcome;Classification=$classification;Before=$Before;After=$After;BeforeState=$BeforeState;AfterState=$AfterState;Limitation='Timestamp progression is an observation, not a captured DHCP exchange.'}
}

function ConvertTo-ContextTime {
    param($Value)
    if ($null -eq $Value -or [string]$Value -eq '') { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return $null }
        return [DateTimeOffset]$Value
    }
    $text = [string]$Value
    if ($text -match '^/Date\((-?\d+)([+-]\d{4})?\)/$') {
        try { $time = [DateTimeOffset]::new(1970,1,1,0,0,0,[TimeSpan]::Zero).AddMilliseconds([double]$Matches[1]) } catch { return $null }
        if ($Matches[2]) {
            $offset = $Matches[2]
            $minutes = ([int]$offset.Substring(1,2)*60 + [int]$offset.Substring(3,2))
            if ($offset[0] -eq '-') { $minutes = -$minutes }
            try { $time = $time.ToOffset([TimeSpan]::FromMinutes($minutes)) } catch { return $null }
        }
        return $time
    }
    if ($text -match '^\d{14}\.\d{6}[+-]\d{3}$') {
        try {
            $date = [datetime]::ParseExact($text.Substring(0,14),'yyyyMMddHHmmss',[Globalization.CultureInfo]::InvariantCulture)
            $minutes = [int]$text.Substring(22,3)
            if ($text[21] -eq '-') { $minutes = -$minutes }
            return [DateTimeOffset]::new($date.AddTicks([long]$text.Substring(15,6)*10),[TimeSpan]::FromMinutes($minutes))
        } catch { return $null }
    }
    # Never silently interpret an offset-free serialized timestamp in this host's zone.
    if ($text -notmatch '(Z|[+-]\d{2}:\d{2})$') { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)) { return $parsed }
    return $null
}

function Get-ContextIdentity {
    param($Value)
    $guid = [guid]::Empty
    if ([guid]::TryParse([string]$Value,[ref]$guid) -and $guid -ne [guid]::Empty) { return $guid.ToString('D') }
    return $null
}

function Get-ContextSource {
    param($Evidence,[string]$Name,$Index)
    $selected = @(); $refs = @(); $checkRefs=@(); $status = 'NotCollected'; $start = $null; $end = $null; $enumerationValid=$false
    for ($ci=0; $ci -lt @($Evidence.Checks).Count; $ci++) {
        $check = $Evidence.Checks[$ci]
        if ($check.Name -ne $Name) { continue }
        $checkRefs += "/Checks/$ci"
        $status = $check.Status; $start = $check.StartedAt; $end = $check.CompletedAt
        if ($status -ne 'Success') { continue }
        $enumerationValid=$check.Data -is [array] -and @($check.Data | Where-Object {$null -eq $_ -or $null -eq $_.InterfaceIndex}).Count -eq 0
        for ($di=0; $di -lt @($check.Data).Count; $di++) {
            if ($check.Data[$di].InterfaceIndex -eq $Index) { $selected += $check.Data[$di]; $refs += "/Checks/$ci/Data/$di" }
        }
    }
    if($checkRefs.Count -gt 1){$status='Ambiguous';$enumerationValid=$false}
    [pscustomobject]@{CheckName=$Name;Status=$status;MatchedRecords=$selected.Count;StartedAt=$start;CompletedAt=$end;EvidenceReferences=$refs;CheckReferences=$checkRefs;EnumerationValid=$enumerationValid;Records=$selected}
}

function Get-EmptyConfigurationAvailability {
    param($Sources,[string]$Field,$Dhcp,[bool]$Complete,[bool]$KnownAdapter)
    if(-not $Complete){return 'Incomplete'}
    if(-not $KnownAdapter){return 'Ambiguous'}
    if($Field -eq 'IPv4'){
        if($Sources.IPAddresses.Status -ne 'Success'){return $Sources.IPAddresses.Status}
        if(-not $Sources.IPAddresses.EnumerationValid){return 'Invalid'}
        # Get-NetIPAddress enumerates configured addresses, not an adapter object.
        # No rows for a known adapter is evidence of no addresses, unlike DNS rows.
        return 'ObservedEmpty'
    }
    if($Sources.DHCPAndGateways.Status -ne 'Success'){return $Sources.DHCPAndGateways.Status}
    if(-not $Sources.DHCPAndGateways.EnumerationValid){return 'Invalid'}
    if($Sources.DHCPAndGateways.MatchedRecords -gt 1){return 'Ambiguous'}
    if($Sources.DHCPAndGateways.MatchedRecords -eq 0){return 'No matching record'}
    $property='DefaultIPGateway';$fallback=$Sources.Routes
    if($Field -eq 'DnsServers'){$property='DNSServerSearchOrder';$fallback=$Sources.DNSServers}
    # Null in the primary field is not proof. Independent, complete fallback
    # evidence must establish absence too. Absent schema fields remain unknown.
    if(-not $Dhcp.PSObject.Properties[$property]){return 'Missing'}
    if($null -ne $Dhcp.$property -and ($Dhcp.$property -isnot [array] -or @($Dhcp.$property).Count -gt 0)){return 'Invalid'}
    if($fallback.Status -ne 'Success'){return $fallback.Status}
    if(-not $fallback.EnumerationValid){return 'Invalid'}
    if($Field -eq 'Gateways'){
        foreach($route in $fallback.Records){
            $prefix=[string]$route.DestinationPrefix -split '/';$network=$null;$length=0
            if($prefix.Count -ne 2 -or -not [Net.IPAddress]::TryParse($prefix[0],[ref]$network) -or -not [int]::TryParse($prefix[1],[ref]$length)){return 'Invalid'}
            $maxLength=128;if($network.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){$maxLength=32}
            if($length -lt 0 -or $length -gt $maxLength){return 'Invalid'}
            if($route.DestinationPrefix -in @('0.0.0.0/0','::/0') -and $route.NextHop -notin @('0.0.0.0','::')){return 'Invalid'}
        }
        return 'ObservedEmpty'
    }
    # Get-DnsClientServerAddress supplies per-family interface objects. No object
    # (or a null ServerAddresses property) does not establish an empty DNS list.
    if($fallback.MatchedRecords -eq 0){return 'No matching record'}
    $families=@()
    foreach($row in $fallback.Records){
        $family=Get-NetworkDisplayLabel AddressFamily $row.AddressFamily
        if($family -notin @('IPv4','IPv6')){return 'Invalid'}
        if($family -in $families){return 'Ambiguous'}
        $families+=$family
        if($row.ServerAddresses -isnot [array]){return 'Missing'}
        if($row.ServerAddresses.Count -ne 0){return 'Invalid'}
    }
    'ObservedEmpty'
}

function Get-DhcpInterfaceContext {
    param($Evidence,[string]$Scope='Current',[string]$ReferenceRoot='')
    $names = @('Adapters','IPAddresses','DHCPAndGateways','DNSServers','InterfacesAndMetrics','Routes')
    $indices = @($Evidence.Checks | Where-Object { $_.Status -eq 'Success' -and $_.Name -in $names } | ForEach-Object { $_.Data } | Where-Object { $null -ne $_.InterfaceIndex } | ForEach-Object { $_.InterfaceIndex } | Sort-Object -Unique)
    foreach ($index in $indices) {
        $sources = [ordered]@{}
        foreach ($name in $names) { $sources[$name] = Get-ContextSource $Evidence $name $index }
        $a = @($sources.Adapters.Records); $d = @($sources.DHCPAndGateways.Records)
        $adapter = $null; $dhcp = $null
        if ($a.Count -eq 1) { $adapter = $a[0] }
        if ($d.Count -eq 1) { $dhcp = $d[0] }
        $ids = @(@($a | ForEach-Object {Get-ContextIdentity $_.InterfaceGuid})+@($d | ForEach-Object {Get-ContextIdentity $_.SettingID}) | Where-Object { $_ } | Select-Object -Unique)
        $id = $null; $basis = 'No stable identity; no cross-snapshot fallback'
        if ($ids.Count -eq 1) { $id = $ids[0]; $basis = 'InterfaceGuid/SettingID, joined within snapshot by interface index' }
        elseif ($ids.Count -gt 1) { $basis = 'Ambiguous: InterfaceGuid and SettingID disagree' }
        if($a.Count -gt 1 -or $sources.Adapters.Status -eq 'Ambiguous' -or $sources.DHCPAndGateways.Status -eq 'Ambiguous'){$id=$null;$basis='Ambiguous: multiple source records/checks for this interface'}
        $kind = 'Unknown'
        if ($adapter.HardwareInterface -is [bool]) { $kind = $(if ($adapter.HardwareInterface) {'Physical'} else {'Virtual/software'}) }
        $ipif = @($sources.InterfacesAndMetrics.Records | Where-Object { [string]$_.AddressFamily -in @('2','IPv4','InterNetwork') })
        $connection = @($ipif | ForEach-Object { Get-NetworkDisplayLabel ConnectionState $_.ConnectionState })
        $disconnected = ($adapter.Status -in @('Down','Disconnected','Disabled','Not Present') -or 'Disconnected' -in $connection)
        $server = $null; $serverState = 'Missing or invalid'
        $parsed = $null
        if ([Net.IPAddress]::TryParse([string]$dhcp.DHCPServer,[ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and [string]$parsed -notin @('0.0.0.0','255.255.255.255') -and $parsed.GetAddressBytes()[0] -lt 224) { $server = $parsed.ToString(); $serverState = 'Selected server recorded' }
        if ($dhcp.DHCPEnabled -eq $false) { $server = $null; $serverState = 'DHCP disabled; any raw server value is retained configuration' }
        $obtained = ConvertTo-ContextTime $dhcp.DHCPLeaseObtained
        $expires = ConvertTo-ContextTime $dhcp.DHCPLeaseExpires
        $at = ConvertTo-ContextTime $sources.DHCPAndGateways.CompletedAt
        $duration = $null; $remaining = $null
        if ($obtained -and $expires -and $expires -ge $obtained) { $duration = ($expires-$obtained).TotalSeconds }
        if ($expires -and $at) { $remaining = ($expires-$at).TotalSeconds }
        # An empty $(if (...) {...}) in a hashtable can retain AutomationNull.Value
        # in Windows PowerShell 5.1; ConvertTo-Json then emits {}. Assign real nulls.
        $obtainedText=$null; $expiresText=$null; $referenceTime=$null
        if($obtained){$obtainedText=$obtained.ToString('o')}
        if($expires){$expiresText=$expires.ToString('o')}
        if($at){$referenceTime=$at.ToString('o')}
        $values = [ordered]@{
            MacAddress=$adapter.MacAddress; LinkState=$adapter.Status; ConnectionState=$connection
            IPv4=@($sources.IPAddresses.Records | Where-Object { [string]$_.AddressFamily -in @('2','IPv4','InterNetwork') -or $_.IPAddress -match '^\d+\.' } | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" } | Sort-Object -Unique)
            DHCPEnabled=$dhcp.DHCPEnabled; SelectedDhcpServer=$server
            Gateways=@($dhcp.DefaultIPGateway | Where-Object { $null -ne $_ -and [string]$_ -ne '' }); DnsServers=@($dhcp.DNSServerSearchOrder | Where-Object { $null -ne $_ -and [string]$_ -ne '' }); DnsDomain=$dhcp.DNSDomain
            LeaseObtained=$obtainedText; LeaseExpires=$expiresText; LeaseDurationSeconds=$duration
        }
        if ($null -ne $values.LinkState -and [string]$values.LinkState -notin @('Up','Down','Disconnected','Disabled','Not Present','Unknown')) {
            $values.LinkState = 'Unknown (' + [string]$values.LinkState + ')'
        }
        # The WMI DNS list preserves preference across families; retain family-labelled inventory too.
        $dnsInventory = @($sources.DNSServers.Records | Select-Object AddressFamily,ServerAddresses)
        $dnsSource = 'DHCPAndGateways'
        if (-not @($dhcp.DNSServerSearchOrder | Where-Object { $_ }).Count -and $dnsInventory.Count) {
            $values.DnsServers = @($dnsInventory | Sort-Object AddressFamily | ForEach-Object { $_.ServerAddresses } | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
            $dnsSource = 'DNSServers'
        }
        $defaultRoutes = @($sources.Routes.Records | Where-Object DestinationPrefix -in @('0.0.0.0/0','::/0'))
        $gatewaySource = 'DHCPAndGateways'
        if (-not @($dhcp.DefaultIPGateway | Where-Object { $_ }).Count -and $defaultRoutes.Count) {
            $values.Gateways = @($defaultRoutes | ForEach-Object NextHop | Where-Object { $_ -and $_ -notin @('0.0.0.0','::') } | Sort-Object -Unique)
            $gatewaySource = 'Routes'
        }
        $availability = [ordered]@{}
        foreach ($field in $values.Keys) {
            $source = 'DHCPAndGateways'
            if ($field -in @('MacAddress','LinkState')) { $source = 'Adapters' }
            if ($field -eq 'ConnectionState') { $source = 'InterfacesAndMetrics' }
            if ($field -eq 'IPv4') { $source = 'IPAddresses' }
            if ($field -eq 'DnsServers') { $source = $dnsSource }
            if ($field -eq 'Gateways') { $source = $gatewaySource }
            $availability[$field] = $(if ($sources[$source].Status -ne 'Success') { $sources[$source].Status } elseif ($sources[$source].MatchedRecords -eq 0) { 'No matching record' } elseif ($null -eq $values[$field] -or @($values[$field]).Count -eq 0 -or [string]$values[$field] -eq '') { 'Missing' } else { 'Available' })
        }
        foreach($field in @('IPv4','Gateways','DnsServers')){
            if(@($values[$field]).Count -eq 0){
                $availability[$field]=Get-EmptyConfigurationAvailability $sources $field $dhcp ($Evidence.CollectionStatus -eq 'Complete') ($a.Count -eq 1 -and [bool]$id -and $sources.Adapters.Status -eq 'Success')
            } elseif($availability[$field] -eq 'Available'){
                foreach($value in $values[$field]){
                    $address=[string]$value;$ip=$null
                    if($field -eq 'IPv4'){$address=($address -split '/')[0]}
                    if(-not [Net.IPAddress]::TryParse($address,[ref]$ip)){$availability[$field]='Invalid';continue}
                    if($field -eq 'IPv4' -and ($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or [string]$value -notmatch '/(\d|[12]\d|3[0-2])$')){$availability[$field]='Invalid'}
                }
                if($field -in @('Gateways','DnsServers') -and $d.Count -gt 1){$availability[$field]='Ambiguous'}
            }
        }
        foreach($dateField in @(@('LeaseObtained','DHCPLeaseObtained'),@('LeaseExpires','DHCPLeaseExpires'))) {
            if($sources.DHCPAndGateways.Status -eq 'Success' -and $d.Count -eq 1) {
                if($dhcp.DHCPEnabled -eq $false){$availability[$dateField[0]]='Not applicable'}
                elseif(-not $dhcp.PSObject.Properties[$dateField[1]]){$availability[$dateField[0]]='MissingProperty'}
                elseif($null -eq $dhcp.($dateField[1])){$availability[$dateField[0]]='ObservedNull'}
                elseif([string]$dhcp.($dateField[1]) -eq ''){$availability[$dateField[0]]='ObservedEmpty'}
                elseif($null -eq $values[$dateField[0]]){$availability[$dateField[0]]='Invalid'}
            }
        }
        if($sources.DHCPAndGateways.Status -eq 'Success' -and $d.Count -eq 1){
            if($dhcp.DHCPEnabled -eq $false){$availability.SelectedDhcpServer='Not applicable';$availability.LeaseDurationSeconds='Not applicable'}
            elseif($null -eq $server -and -not [string]::IsNullOrWhiteSpace([string]$dhcp.DHCPServer)){$availability.SelectedDhcpServer='Invalid'}
            if($obtained -and $expires -and $expires -lt $obtained){$availability.LeaseDurationSeconds='Invalid'}
        }
        # Raw records remain in Checks (or the selected baseline Checks store), once.
        foreach($name in $names) {
            $s=$sources[$name]
            $sources[$name]=[pscustomobject]@{CheckName=$s.CheckName;Status=$s.Status;MatchedRecords=$s.MatchedRecords;StartedAt=$s.StartedAt;CompletedAt=$s.CompletedAt;Scope=$Scope;RunId=$Evidence.RunId
                EvidenceReferences=@($s.EvidenceReferences | ForEach-Object {$ReferenceRoot+$_});CheckReferences=@($s.CheckReferences | ForEach-Object {$ReferenceRoot+$_});EnumerationValid=$s.EnumerationValid}
        }
        [pscustomobject]@{StableIdentity=$id;IdentityBasis=$basis;InterfaceIndex=$index;Alias=$adapter.Name;Description=$adapter.InterfaceDescription;Kind=$kind
            Disconnected=$disconnected;ConfigurationNote=$(if($disconnected){'Retained configuration on a disconnected adapter.'}else{'Configured values; gateway/DNS origin is not established.'})
            Values=[pscustomobject]$values;Availability=[pscustomobject]$availability;Sources=[pscustomobject]$sources;DnsValueSource=$dnsSource;GatewayValueSource=$gatewaySource
            SelectedDhcpServerState=$serverState;SelectedDhcpServerRaw=$dhcp.DHCPServer
            LeaseRaw=[pscustomobject]@{LeaseObtained=$dhcp.DHCPLeaseObtained;LeaseExpires=$dhcp.DHCPLeaseExpires}
            LeaseReferenceTime=$referenceTime;LeaseRemainingSeconds=$remaining
            LeaseTimeNote='Missing, invalid or offset-free dates are unknown; remaining time is relative to DHCP source completion, not report viewing time.'
            CompetingDhcpServers='Not assessed'}
    }
}

function Assert-ExpectationRule {
    param($Rule)
    if ($null -eq $Rule -or $Rule -isnot [pscustomobject]) { throw 'Expectation rule must be an object.' }
    foreach ($property in $Rule.PSObject.Properties) {
        if ($property.Name -notin @('AllowedDhcpServers','AllowedGateways','DnsServers')) { throw "Unknown expectation field: $($property.Name)" }
        if ($property.Value -isnot [array] -or $property.Value.Count -eq 0) { throw 'Expectation address lists must be nonempty JSON arrays.' }
        foreach ($value in $property.Value) {
            $ip = $null
            if ($value -isnot [string] -or -not [Net.IPAddress]::TryParse($value,[ref]$ip) -or $value -in @('0.0.0.0','255.255.255.255','::')) { throw 'Expectations require usable IP address literals.' }
        }
    }
}

function Read-ContextInput {
    param([string]$Path,[ValidateSet('Baseline','Expectations')][string]$Kind,[string]$ComputerName)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer) { throw 'Optional input must be a JSON file.' }
    $inputObject = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($Kind -eq 'Baseline') {
        if ($inputObject.SchemaVersion -notin @(6,7,8,9,10,11) -or $inputObject.Mode -ne 'Snapshot' -or -not $inputObject.RunId -or $null -eq $inputObject.Checks) { throw 'Unsupported or malformed baseline; expected snapshot schema 6, 7, 8, 9, 10 or 11.' }
        if (-not $ComputerName -or $inputObject.ComputerName -ne $ComputerName) { throw 'Baseline computer identity is incompatible.' }
        if (-not (ConvertTo-ContextTime $inputObject.StartedAt)) { throw 'Baseline start timestamp is invalid or lacks an offset.' }
        # Retain only the six check families consumed by these features. Never
        # import the baseline's derived contexts, comparisons or older history.
        $selectedChecks=@($inputObject.Checks | Where-Object Name -in @('Adapters','DHCPAndGateways','IPAddresses','DNSServers','InterfacesAndMetrics','Routes'))
        $selection=[pscustomobject]@{RunId=$inputObject.RunId;CollectionStatus=$inputObject.CollectionStatus;Checks=$selectedChecks}
        return [pscustomobject]@{Identity=($inputObject | Select-Object ComputerName,RunId,StartedAt,CompletedAt,CollectionStatus,SchemaVersion);AdapterInventoryStatus=@($selectedChecks | Where-Object Name -eq 'Adapters' | Select-Object -Last 1).Status;Checks=$selectedChecks;Interfaces=@(Get-DhcpInterfaceContext $selection Baseline '/ContextEvidence/Baseline')}
    }
    if ($inputObject.Version -ne 1) { throw 'Expectations Version must be 1.' }
    foreach ($property in $inputObject.PSObject.Properties.Name) { if ($property -notin @('Version','Defaults','Interfaces')) { throw "Unknown expectations field: $property" } }
    if ($null -ne $inputObject.Defaults) { Assert-ExpectationRule $inputObject.Defaults }
    $seen = @()
    if ($null -ne $inputObject.Interfaces -and $inputObject.Interfaces -isnot [array]) { throw 'Interfaces must be a JSON array.' }
    foreach ($entry in $inputObject.Interfaces) {
        $id = Get-ContextIdentity $entry.InterfaceGuid
        if (-not $id -or $id -in $seen) { throw 'Interface overrides require unique nonempty InterfaceGuid GUIDs.' }
        foreach ($property in $entry.PSObject.Properties.Name) { if ($property -notin @('InterfaceGuid','Rules')) { throw "Unknown interface override field: $property" } }
        Assert-ExpectationRule $entry.Rules
        $entry.InterfaceGuid = $id; $seen += $id
    }
    $inputObject
}

function New-ContextReference {
    param([string]$Scope,[string]$RunId,[int]$Index)
    if($Index -lt 0){return $null}
    $path='/DhcpSummary/Interfaces/'+$Index
    if($Scope -eq 'Baseline'){$path='/ContextEvidence/Baseline/Interfaces/'+$Index}
    [pscustomobject]@{Scope=$Scope;RunId=$RunId;Path=$path}
}

function Get-ComparisonAdapterState {
    param($Interface)
    $state='Unknown'
    if($Interface.Disconnected){$state='Disconnected'}
    elseif($Interface.Values.LinkState -eq 'Up' -or 'Connected' -in @($Interface.Values.ConnectionState)){$state='Connected'}
    [pscustomobject]@{Alias=$Interface.Alias;InterfaceIndex=$Interface.InterfaceIndex;LinkState=$Interface.Values.LinkState;ConnectionState=@($Interface.Values.ConnectionState | Where-Object {$null -ne $_});State=$state}
}

function Get-AdapterPresenceCoverage {
    param($Checks,$Interfaces,[string]$CollectionStatus,[string]$Scope,[string]$RunId)
    $inventory=@($Checks | Where-Object Name -eq 'Adapters')
    $reference=$null
    if($inventory.Count -eq 1){
        $path='/Checks/'+[array]::IndexOf(@($Checks),$inventory[0])
        if($Scope -eq 'Baseline'){$path='/ContextEvidence/Baseline'+$path}
        $reference=[pscustomobject]@{Scope=$Scope;RunId=$RunId;Path=$path}
    }
    $reason='SnapshotIncomplete';$detail='Snapshot is incomplete; adapter absence cannot be established.';$known=@()
    if($CollectionStatus -eq 'Complete'){
        $reason='InventoryUnavailable';$detail='One successful adapter inventory is required.'
        if($inventory.Count -eq 1 -and $inventory[0].Status -eq 'Success'){
            $reason='IdentityEvidenceInsufficient';$detail='An inventoried adapter has missing, conflicting, duplicate or uncorrelatable stable identity evidence.'
            $valid=$inventory[0].Data -is [array]
            foreach($adapter in $inventory[0].Data){
                $rows=@($Interfaces | Where-Object {$null -ne $adapter.InterfaceIndex -and $_.InterfaceIndex -eq $adapter.InterfaceIndex})
                if($rows.Count -ne 1 -or -not $rows[0].StableIdentity -or $rows[0].Sources.Adapters.MatchedRecords -ne 1 -or $rows[0].Sources.DHCPAndGateways.MatchedRecords -gt 1){$valid=$false;continue}
                $id=$rows[0].StableIdentity
                if($id -in $known){$valid=$false}
                $known+=$id
            }
            if($valid){$reason='CompleteIdentifiedInventory';$detail='Complete successful adapter inventory with unique stable identities; non-inventory IP-only records do not affect absence assessment.'}
        }
    }
    [pscustomobject]@{Sufficient=($reason -eq 'CompleteIdentifiedInventory');ReasonCode=$reason;Detail=$detail;Identities=$known;Reference=$reference}
}

function Compare-DhcpContext {
    param($Current,$Baseline,$Evidence)
    $changes = @(); $matched = @()
    $baselineCoverage=Get-AdapterPresenceCoverage $Baseline.Checks $Baseline.Interfaces $Baseline.Identity.CollectionStatus Baseline $Baseline.Identity.RunId
    $currentCoverage=Get-AdapterPresenceCoverage $Evidence.Checks $Current $Evidence.CollectionStatus Current $Evidence.RunId
    $presenceDetail='Baseline: '+$baselineCoverage.Detail+' Current: '+$currentCoverage.Detail
    foreach ($now in $Current) {
        $old = @($Baseline.Interfaces | Where-Object { $now.StableIdentity -and $_.StableIdentity -eq $now.StableIdentity })
        $duplicate = @($Current | Where-Object { $now.StableIdentity -and $_.StableIdentity -eq $now.StableIdentity }).Count -gt 1
        if (-not $now.StableIdentity -or $old.Count -gt 1 -or $duplicate) {
            $changes += [pscustomobject]@{Identity=$now.StableIdentity;InterfaceIndex=$now.InterfaceIndex;Field='Adapter';Outcome='Not assessed';Detail='Missing or ambiguous stable identity; no alias/MAC/index fallback.'}; continue
        }
        if ($old.Count -eq 0) {
            $known = $baselineCoverage.Sufficient -and $currentCoverage.Sufficient -and $now.StableIdentity -in $currentCoverage.Identities
            $changes += [pscustomobject]@{Identity=$now.StableIdentity;Field='Adapter';Outcome=$(if($known){'Appeared'}else{'Not assessed'});Detail=$presenceDetail;BeforePresenceReason=$baselineCoverage.ReasonCode;AfterPresenceReason=$currentCoverage.ReasonCode}; continue
        }
        $matched += $now.StableIdentity
        foreach ($field in $now.Values.PSObject.Properties.Name) {
            $before = $old[0].Values.$field; $after = $now.Values.$field
            $available = ($old[0].Availability.$field -in @('Available','ObservedEmpty') -and $now.Availability.$field -in @('Available','ObservedEmpty'))
            $left = @($before); $right = @($after)
            if ($field -in @('IPv4','Gateways','ConnectionState')) { $left = @($left | Sort-Object -Unique); $right = @($right | Sort-Object -Unique) }
            $equal = (ConvertTo-Json -InputObject $left -Compress -Depth 5) -ceq (ConvertTo-Json -InputObject $right -Compress -Depth 5)
            if($available -and $field -in @('LeaseObtained','LeaseExpires')) {
                $equal=(ConvertTo-ContextTime $before).UtcDateTime.Ticks -eq (ConvertTo-ContextTime $after).UtcDateTime.Ticks
            }
            $outcome = 'Unchanged'
            if (-not $available) { $outcome = 'Not assessed' } elseif (-not $equal) { $outcome = 'Changed' }
            $lease=$null
            if($field -in @('LeaseObtained','LeaseExpires')){
                $bs=$old[0].Availability.$field;$ns=$now.Availability.$field
                if($bs -notin @('Available','ObservedNull','ObservedEmpty','Invalid','MissingProperty')){$bs='Unavailable'}
                if($ns -notin @('Available','ObservedNull','ObservedEmpty','Invalid','MissingProperty')){$ns='Unavailable'}
                $lease=Compare-LeaseTimestamp $old[0].LeaseRaw.$field $now.LeaseRaw.$field $bs $ns
                $outcome=$lease.Outcome;if($outcome -eq 'LeaseRefreshed'){$outcome='Lease refreshed'}
            }
            $changes += [pscustomobject]@{Identity=$now.StableIdentity;Field=$field;Outcome=$outcome;Before=$before;After=$after;BeforeAvailability=$old[0].Availability.$field;AfterAvailability=$now.Availability.$field
                LeaseTimestamp=$lease;Basis=$now.IdentityBasis}
        }
    }
    foreach ($old in $Baseline.Interfaces) {
        if ($old.StableIdentity -and $old.StableIdentity -notin $matched -and $old.StableIdentity -notin @($Current.StableIdentity)) {
            $known = $baselineCoverage.Sufficient -and $currentCoverage.Sufficient -and @($Baseline.Interfaces | Where-Object StableIdentity -eq $old.StableIdentity).Count -eq 1 -and $old.StableIdentity -in $baselineCoverage.Identities
            $changes += [pscustomobject]@{Identity=$old.StableIdentity;Field='Adapter';Outcome=$(if($known){'Disappeared'}else{'Not assessed'});Detail=$presenceDetail;BeforePresenceReason=$baselineCoverage.ReasonCode;AfterPresenceReason=$currentCoverage.ReasonCode}
        }
    }
    foreach($change in $changes) {
        if($change.Field -eq 'Adapter'){
            $change | Add-Member NoteProperty BeforeInventoryReference $baselineCoverage.Reference -Force
            $change | Add-Member NoteProperty AfterInventoryReference $currentCoverage.Reference -Force
        }
        $beforeRows=@($Baseline.Interfaces | Where-Object {$change.Identity -and $_.StableIdentity -eq $change.Identity})
        $afterRows=@($Current | Where-Object {$change.Identity -and $_.StableIdentity -eq $change.Identity})
        $beforeItem=$null;$afterItem=$null;$beforeRef=$null;$afterRef=$null
        if($beforeRows.Count -eq 1){$beforeItem=$beforeRows[0];$beforeRef=New-ContextReference Baseline $Baseline.Identity.RunId ([array]::IndexOf(@($Baseline.Interfaces),$beforeItem))}
        if($afterRows.Count -eq 1){$afterItem=$afterRows[0];$afterRef=New-ContextReference Current $Evidence.RunId ([array]::IndexOf(@($Current),$afterItem))}
        $beforeState=Get-ComparisonAdapterState $beforeItem;$afterState=Get-ComparisonAdapterState $afterItem
        $note='State evidence is unknown or ambiguous.'
        if($beforeState.State -ne 'Unknown' -and $afterState.State -ne 'Unknown') {
            $note='State: '+$beforeState.State+' -> '+$afterState.State+'. Configured changes do not establish a connectivity fault.'
            $sameState=$beforeState.LinkState -eq $afterState.LinkState -and (@($beforeState.ConnectionState) -join '|') -eq (@($afterState.ConnectionState) -join '|')
            if(-not $sameState){$note+=' Link/connection transition: '+$beforeState.LinkState+'/'+(@($beforeState.ConnectionState) -join ', ')+' -> '+$afterState.LinkState+'/'+(@($afterState.ConnectionState) -join ', ')+'.'}
            elseif($beforeState.State -eq 'Disconnected' -and $afterState.State -eq 'Disconnected' -and $change.Outcome -in @('Changed','Lease refreshed')){$note='Retained configuration changed on a disconnected adapter.'}
        }
        $change | Add-Member NoteProperty BeforeReference $beforeRef -Force
        $change | Add-Member NoteProperty AfterReference $afterRef -Force
        $change | Add-Member NoteProperty BeforeContext $beforeState -Force
        $change | Add-Member NoteProperty AfterContext $afterState -Force
        $change | Add-Member NoteProperty StateNote $note -Force
    }
    $counts=[pscustomobject]@{Changed=@($changes | Where-Object Outcome -in @('Changed','Appeared','Disappeared')).Count;LeaseRefreshed=@($changes | Where-Object Outcome -eq 'Lease refreshed').Count;Unchanged=@($changes | Where-Object Outcome -eq 'Unchanged').Count;NotAssessed=@($changes | Where-Object Outcome -eq 'Not assessed').Count}
    [pscustomobject]@{Status='Compared';BaselineIdentity=$Baseline.Identity;CurrentIdentity=($Evidence | Select-Object ComputerName,RunId,StartedAt,CompletedAt,CollectionStatus);Changes=$changes;Counts=$counts
        Limitation='Two observations only; no continuous health/configuration inference. Lease refreshed does not establish a captured renewal exchange or its cause.'}
}

function Test-DhcpExpectations {
    param($Interfaces,$Expectations)
    foreach ($interface in $Interfaces) {
        $ambiguousIdentity = $interface.StableIdentity -and @($Interfaces | Where-Object StableIdentity -eq $interface.StableIdentity).Count -gt 1
        $rules = [ordered]@{}
        if ($Expectations.Defaults) { foreach ($p in $Expectations.Defaults.PSObject.Properties) { $rules[$p.Name] = $p.Value } }
        $override = @($Expectations.Interfaces | Where-Object { $_.InterfaceGuid -eq $interface.StableIdentity })
        if ($override.Count -eq 1) { foreach ($p in $override[0].Rules.PSObject.Properties) { $rules[$p.Name] = $p.Value } }
        foreach ($spec in @(@('AllowedDhcpServers','SelectedDhcpServer'),@('AllowedGateways','Gateways'),@('DnsServers','DnsServers'))) {
            $key = $spec[0]; $field = $spec[1]; $observed = @($interface.Values.$field | Where-Object {$null -ne $_}); $outcome = 'Not assessed'; $reason = 'No expectation supplied.'
            if ($rules.Contains($key)) {
                $reason = 'Missing, ambiguous or disconnected evidence.'
                if ($key -eq 'AllowedDhcpServers' -and $interface.Values.DHCPEnabled -eq $false) { $outcome = 'Not applicable'; $reason = 'DHCP is disabled.' }
                elseif (-not $ambiguousIdentity -and -not $interface.Disconnected -and $interface.Values.LinkState -eq 'Up' -and $interface.Availability.$field -eq 'Available' -and ($key -ne 'AllowedDhcpServers' -or $interface.Values.DHCPEnabled -eq $true) -and ($interface.StableIdentity -or @($Expectations.Interfaces).Count -eq 0)) {
                    $invalid = $false
                    $normalized = @($observed | ForEach-Object { $ip=$null; if([Net.IPAddress]::TryParse([string]$_,[ref]$ip)){$ip.ToString()}else{$invalid=$true} })
                    $allowed = @($rules[$key] | ForEach-Object { ([Net.IPAddress]::Parse($_)).ToString() })
                    $match = @($normalized | Where-Object { $_ -notin $allowed }).Count -eq 0
                    if ($key -eq 'DnsServers') { $match = (($normalized -join '|') -ceq ($allowed -join '|')) }
                    $outcome = $(if($match){'Match'}else{'Mismatch'}); $reason = $(if($match){'Within supplied expectations.'}else{'Outside supplied expectations; not proof of a rogue server or root cause.'})
                    if ($invalid -or -not $normalized.Count) { $outcome='Not assessed';$reason='Observed address is missing or invalid.' }
                }
            }
            [pscustomobject]@{Identity=$interface.StableIdentity;InterfaceIndex=$interface.InterfaceIndex;Field=$key;Outcome=$outcome;Reason=$reason;Observed=$observed;EffectiveExpectations=[pscustomobject]$rules;EvidenceReference=New-ContextReference Current $interface.Sources.Adapters.RunId ([array]::IndexOf(@($Interfaces),$interface))}
        }
    }
}

function ConvertTo-EventMacIdentity {
    param($Value)
    $text=([string]$Value -replace '^0x','') -replace '[-: ]',''
    if($text -notmatch '^[0-9a-fA-F]{12}$' -or $text -eq '000000000000'){return $null}
    if(([Convert]::ToInt32($text.Substring(0,2),16) -band 1) -ne 0){return $null}
    $text.ToUpperInvariant()
}

function Get-EventIdentityCoverage {
    param($Evidence,$Interfaces,[string]$Type)
    $checks=@($Evidence.Checks | Where-Object Name -eq 'Adapters')
    $status='NotCollected';$code='AdapterInventoryMissing';$reason='Adapter inventory was not collected.'
    $sufficient=$false;$excluded=0;$missing=0
    if($checks.Count){
        $inventory=$checks[-1];$status=$inventory.Status
        $code='AdapterInventoryNotSuccessful';$reason='Adapter inventory status is '+$status+'; absence cannot be established.'
        if($status -eq 'Success'){
            $records=@($inventory.Data | Where-Object {$null -ne $_})
            $code='EmptyAdapterInventory';$reason='Successful adapter inventory returned no records; identity coverage is unknown.'
            if($records.Count){
                foreach($record in $records){
                    if($Type -eq 'MAC'){
                        $mac=ConvertTo-EventMacIdentity $record.MacAddress
                        if($mac){
                            # A raw identity lost by an ambiguous within-snapshot join must not
                            # become a false negative when matching the derived interfaces.
                            if(-not @($Interfaces | Where-Object {(ConvertTo-EventMacIdentity $_.Values.MacAddress) -eq $mac}).Count){$missing++}
                            continue
                        }
                        $typeValue=[string]$record.InterfaceType
                        $nonMacTypes=@([string][int][Net.NetworkInformation.NetworkInterfaceType]::Loopback,[string][int][Net.NetworkInformation.NetworkInterfaceType]::Tunnel,[string][int][Net.NetworkInformation.NetworkInterfaceType]::Ppp,'Loopback','Tunnel','Ppp')
                        $emptyMac=[string]::IsNullOrWhiteSpace([string]$record.MacAddress) -or (([string]$record.MacAddress -replace '[-: ]','') -eq '000000000000')
                        if($emptyMac -and $typeValue -in $nonMacTypes -and $record.HardwareInterface -is [bool] -and -not $record.HardwareInterface){$excluded++;continue}
                        # Virtual alone is not proof that a MAC is inapplicable. Ethernet-like,
                        # physical and unknown types still require usable identity evidence.
                        $missing++
                    }
                }
                if($Type -eq 'Guid'){$missing=@($Interfaces | Where-Object {-not $_.StableIdentity}).Count}
                $sufficient=$missing -eq 0
                if($sufficient){$code='SufficientIdentityEvidence';$reason="Successful adapter inventory has sufficient $Type identity coverage; $excluded explicitly non-MAC interface(s) excluded."}
                else{$code='RelevantIdentityEvidenceMissing';$reason="$missing adapter identity record(s) are missing, invalid or cannot be correlated. Virtual status alone does not make a MAC inapplicable; unknown applicability prevents establishing absence."}
            }
        }
    }
    [pscustomobject]@{CanAssessAbsence=$sufficient;InventoryStatus=$status;ReasonCode=$code;Explanation=$reason;ExcludedNonMacInterfaces=$excluded;InsufficientIdentityRecords=$missing}
}

function Get-HistoricalEventContext {
    param($Evidence,$Interfaces,$Baseline)
    $start = ConvertTo-ContextTime $Evidence.StartedAt
    $coverageByType=@{}
    for ($ci=0; $ci -lt @($Evidence.Checks).Count; $ci++) {
        $check = $Evidence.Checks[$ci]
        if ($check.Name -notlike 'Events:*' -or $check.Status -ne 'Success') { continue }
        for ($di=0; $di -lt @($check.Data).Count; $di++) {
            $batch = $check.Data[$di]
            for ($ei=0; $ei -lt @($batch.Events).Count; $ei++) {
                $event = $batch.Events[$ei]; $identifiers = @(); $xmlError = $null
                try {
                    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
                    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new([string]$event.Xml),$settings)
                    try { $xml = [Xml.XmlDocument]::new(); $xml.XmlResolver = $null; $xml.Load($reader) } finally { $reader.Dispose() }
                    foreach ($node in $xml.SelectNodes('//*[local-name()="EventData"]/* | //*[local-name()="UserData"]//*[not(*)]')) {
                        $name = $node.LocalName; if ($node.Attributes['Name']) { $name = $node.Attributes['Name'].Value }
                        $type = $null; $value = $null
                        if ($name -match '^(InterfaceGuid|InterfaceId|AdapterGuid|SettingID)$') { $type='Guid'; $value=Get-ContextIdentity $node.InnerText }
                        if ($name -match '^(MacAddress|MAC|HWAddress|HardwareAddress|AdapterAddress|ClientHardwareAddress)$' -and $node.InnerText -match '^(?:0x)?(?:[0-9a-fA-F]{2}[-: ]?){5}[0-9a-fA-F]{2}$') { $type='MAC'; $value=(($node.InnerText -replace '^0x','') -replace '[-: ]','').ToUpperInvariant() }
                        if ($name -match '^(InterfaceIndex|IfIndex|InterfaceName|AdapterName|InterfaceLuid)$') { $type='Unstable identifier'; $value=$node.InnerText }
                        if ($value) { $identifiers += [pscustomobject]@{Field=$name;Type=$type;Value=$value;Raw=$node.InnerText} }
                    }
                } catch { $xmlError = $_.Exception.Message }
                $correlations = @()
                foreach ($identifier in $identifiers) {
                    if ($identifier.Type -eq 'Unstable identifier') {
                        $correlations += [pscustomobject]@{Identifier=$identifier;Confidence='Not assessed';ReasonCode='UnstableIdentifier';Reason='Index/name/LUID may change or be reused; not sufficient for identity matching.';NoCurrentMacMatch=$null;Basis='Structured XML identifier retained without current attribution.'}
                        continue
                    }
                    $current = @($Interfaces | Where-Object { if($identifier.Type -eq 'Guid'){ $_.StableIdentity -eq $identifier.Value }else{ (ConvertTo-EventMacIdentity $_.Values.MacAddress) -eq $identifier.Value } })
                    $historical = @($Baseline.Interfaces | Where-Object { if($identifier.Type -eq 'Guid'){ $_.StableIdentity -eq $identifier.Value }else{ (ConvertTo-EventMacIdentity $_.Values.MacAddress) -eq $identifier.Value } })
                    if(-not $coverageByType.ContainsKey($identifier.Type)){$coverageByType[$identifier.Type]=Get-EventIdentityCoverage $Evidence $Interfaces $identifier.Type}
                    $coverage=$coverageByType[$identifier.Type]
                    $inventoryStatus=$coverage.InventoryStatus;$canAssessAbsence=$coverage.CanAssessAbsence
                    $reasonCode=$coverage.ReasonCode;$reason=$coverage.Explanation
                    if($identifier.Type -eq 'MAC' -and -not (ConvertTo-EventMacIdentity $identifier.Value)){$canAssessAbsence=$false;$reasonCode='InvalidEventMac';$reason='Structured identifier is not a usable 48-bit unicast MAC.'}
                    $confidence='Not assessed'
                    if($current.Count -gt 1){$confidence='Ambiguous match';$reasonCode='MultipleCurrentMatches';$reason='The structured identifier matches multiple current interfaces.'}
                    elseif($current.Count -eq 1){$confidence='Current exact identifier match';$reasonCode='ExactCurrentMatch';$reason='One current interface has this structured identifier; no causal attribution.'}
                    elseif($historical.Count -gt 1 -and $canAssessAbsence){$confidence='Ambiguous match';$reasonCode='MultipleHistoricalMatches';$reason='No current identifier match; multiple baseline interfaces match.'}
                    elseif($canAssessAbsence -and $historical.Count -eq 1){$confidence='Historical-only match';$reasonCode='HistoricalOnlyMatch';$reason='No current identifier match; one interface in the identified baseline matches. This does not establish identity at event time.'}
                    elseif($canAssessAbsence){$confidence='No current identifier match';$reasonCode='NoCurrentIdentifierMatch';$reason=$coverage.Explanation+' No current identifier match was found.'}
                    $noMacMatch=$null
                    if($identifier.Type -eq 'MAC' -and ($canAssessAbsence -or $current.Count)){$noMacMatch=($current.Count -eq 0)}
                    $correlations += [pscustomobject]@{Identifier=$identifier;CurrentMatches=@($current | ForEach-Object {New-ContextReference Current $Evidence.RunId ([array]::IndexOf(@($Interfaces),$_))});Basis='Exact identifier in structured event XML';Confidence=$confidence;ReasonCode=$reasonCode;Reason=$reason
                        NoCurrentMacMatch=$noMacMatch;CurrentInventoryStatus=$inventoryStatus;MatchLimitation='Available snapshot identity associations only, not identity at event time or causal attribution. Conflicting identifiers remain separate.';HistoricalMatches=@($historical | ForEach-Object {New-ContextReference Baseline $Baseline.Identity.RunId ([array]::IndexOf(@($Baseline.Interfaces),$_))});HistoricalProvenance=$Baseline.Identity}
                }
                $time = ConvertTo-ContextTime $event.TimeCreated
                $eventTime=$null;$age=$null
                if($time){$eventTime=$time.ToString('o')}
                if($time -and $start){$age=($start-$time).TotalSeconds}
                $description='Description unavailable'
                if(-not [string]::IsNullOrWhiteSpace([string]$event.Message)){$description=([string]$event.Message -replace '\s+',' ').Trim();if($description.Length -gt 180){$description=$description.Substring(0,180)+'...'}}
                $correlationSummary=@($correlations | ForEach-Object Confidence | Select-Object -Unique) -join '; '
                if(-not $correlationSummary){$correlationSummary='Not assessed: no recognized structured identifier'}
                $assessmentReasons=@($correlations | Where-Object Confidence -eq 'Not assessed' | Select-Object ReasonCode,Reason)
                if(-not $identifiers.Count){$assessmentReasons=@([pscustomobject]@{ReasonCode='NoRecognizedStructuredIdentifier';Reason='No recognized structured XML identifier; message text is not used for identity matching.'})}
                [pscustomobject]@{EvidenceReference="/Checks/$ci/Data/$di/Events/$ei";RawReference=[pscustomobject]@{Scope='Current';RunId=$Evidence.RunId;Path="/Checks/$ci/Data/$di/Events/$ei"};CheckName=$check.Name;SourceStartedAt=$check.StartedAt;SourceCompletedAt=$check.CompletedAt;LimitReached=$batch.LimitReached
                    EventTime=$eventTime;AgeSeconds=$age;EventId=$event.Id;Provider=$event.ProviderName;Description=$description;CorrelationSummary=$correlationSummary;RelationToSnapshotStart=$(if(-not $time -or -not $start){'Unknown'}elseif($time -le $start){'At or before snapshot start'}else{'After snapshot start'})
                    Identifiers=$identifiers;Correlations=$correlations;AssessmentReasons=$assessmentReasons;XmlError=$xmlError;Note='Historical event evidence, not a current fault diagnosis. No universal stale-event threshold; unrecognized XML fields are not guessed from localized messages.'}
            }
        }
    }
}

function Update-DhcpContext {
    param($Evidence)
    $interfaces = @(Get-DhcpInterfaceContext $Evidence)
    $baseline = $null; $expectations = $null; $storedBaseline=$Evidence.ContextEvidence.Baseline
    $comparison = [pscustomobject]@{Status='Not requested'}; $assessment = [pscustomobject]@{Status='Not requested';Results=@()}
    foreach ($inputCheck in @($Evidence.ContextInputs)) {
        if ($inputCheck.Name -eq 'Baseline') {
            if ($inputCheck.Status -eq 'Success') {
                $candidate=@($inputCheck.Data)[0]
                if($candidate.Identity){$storedBaseline=$candidate}
                $baseline=$storedBaseline
                $inputCheck.Data=@([pscustomobject]@{Scope='Baseline';RunId=$baseline.Identity.RunId;Path='/ContextEvidence/Baseline'})
                if ((ConvertTo-ContextTime $baseline.Identity.StartedAt) -gt (ConvertTo-ContextTime $Evidence.StartedAt)) {
                    $baseline = $null
                    $comparison = [pscustomobject]@{Status='Failed';Error='Baseline starts after current snapshot; it is not a previous snapshot.'}
                } else { $comparison = Compare-DhcpContext $interfaces $baseline $Evidence }
            }
            else { $comparison = [pscustomobject]@{Status=$inputCheck.Status;Error=$inputCheck.Error} }
        }
        if ($inputCheck.Name -eq 'Expectations') {
            if ($inputCheck.Status -eq 'Success') { $expectations = @($inputCheck.Data)[0]; $assessment = [pscustomobject]@{Status='Evaluated';EffectiveInput=$expectations;Results=@(Test-DhcpExpectations $interfaces $expectations)} }
            else { $assessment = [pscustomobject]@{Status=$inputCheck.Status;Error=$inputCheck.Error;Results=@()} }
        }
    }
    $Evidence | Add-Member NoteProperty DhcpSummary ([pscustomobject]@{CompetingDhcpServers='Not assessed';Limitation='One selected DHCP server and successful client probes do not establish that only one DHCP server exists.';Interfaces=$interfaces}) -Force
    $Evidence | Add-Member NoteProperty ContextEvidence ([pscustomobject]@{ContractVersion=4;Current=[pscustomobject]@{Identity=($Evidence | Select-Object ComputerName,RunId,StartedAt,CompletedAt,CollectionStatus);ChecksPath='/Checks'};Baseline=$storedBaseline}) -Force
    $Evidence | Add-Member NoteProperty SnapshotComparison $comparison -Force
    $Evidence | Add-Member NoteProperty ExpectationAssessment $assessment -Force
    $Evidence | Add-Member NoteProperty HistoricalEventContext (@(Get-HistoricalEventContext $Evidence $interfaces $baseline)) -Force
}

function Get-ContextAnchor {
    param([string]$Path)
    if($Path -match '^(/Checks/\d+)'){$Path=$Matches[1]}
    elseif($Path -match '^(/ContextEvidence/Baseline/Checks/\d+)'){$Path=$Matches[1]}
    'context-'+($Path -replace '[^A-Za-z0-9_-]','-')
}

function Format-ContextAge {
    param($Seconds)
    if($null -eq $Seconds){return 'Age unknown (timestamp unavailable)'}
    $amount=[Math]::Abs([double]$Seconds);$unit='seconds'
    if($amount -ge 86400){$amount/=86400;$unit='days'}
    elseif($amount -ge 3600){$amount/=3600;$unit='hours'}
    elseif($amount -ge 60){$amount/=60;$unit='minutes'}
    $direction='before snapshot start';if($Seconds -lt 0){$direction='after snapshot start (future-dated)'}
    '{0:0.##} {1} {2}' -f $amount,$unit,$direction
}

function Format-ContextTimestamp {
    param($Value)
    $date=ConvertTo-ContextTime $Value
    if($date){return $date.ToString('yyyy-MM-dd HH:mm:ss zzz')}
    'Timestamp unavailable'
}

function ConvertTo-ContextLink {
    param($Reference,[string]$Label='Evidence')
    if(-not $Reference.Path){return ''}
    '<a href="#'+(Get-ContextAnchor $Reference.Path)+'">'+[Net.WebUtility]::HtmlEncode($Label)+'</a>'
}

function ConvertTo-ComparisonRowsHtml {
    param([object[]]$Rows)
    $html=[Text.StringBuilder]::new();$encode={param($x)[Net.WebUtility]::HtmlEncode([string]$x)}
    $labels=@{MacAddress='MAC address';LinkState='Link state';ConnectionState='Connection state';IPv4='IPv4 addresses / prefixes';DHCPEnabled='DHCP enabled';SelectedDhcpServer='Selected DHCP server';Gateways='Configured gateways';DnsServers='Configured DNS servers';DnsDomain='DNS domain';LeaseObtained='Lease obtained';LeaseExpires='Lease expires';LeaseDurationSeconds='Lease duration (seconds)';Adapter='Adapter presence'}
    $null=$html.Append('<table><tr><th>Adapter</th><th>Field</th><th>Outcome</th><th>Baseline</th><th>Current</th><th>State context / evidence</th></tr>')
    foreach($row in $Rows){
        $beforeLabel='Absent or unidentified';$afterLabel='Absent or unidentified'
        if($null -ne $row.BeforeContext.InterfaceIndex){$beforeLabel="$($row.BeforeContext.Alias) (interface $($row.BeforeContext.InterfaceIndex))"}
        if($null -ne $row.AfterContext.InterfaceIndex){$afterLabel="$($row.AfterContext.Alias) (interface $($row.AfterContext.InterfaceIndex))"}
        $label=$beforeLabel+' -> '+$afterLabel
        $field=$labels[$row.Field];if(-not $field){$field=$row.Field}
        $beforeValue=@($row.Before) -join ', ';$afterValue=@($row.After) -join ', '
        if($row.Field -in @('LeaseObtained','LeaseExpires')){$beforeValue=Format-ContextTimestamp $row.Before;$afterValue=Format-ContextTimestamp $row.After}
        $null=$html.Append('<tr>')
        $classification=[string]$row.Outcome
        if($row.LeaseTimestamp){$classification+=' / '+$row.LeaseTimestamp.Classification}
        foreach($value in @($label,$field,$classification,$beforeValue,$afterValue)){$null=$html.Append('<td>'+(& $encode $value)+'</td>')}
        $null=$html.Append('<td>'+(& $encode $row.StateNote)+'<details><summary>Identity and state details</summary><p>Stable GUID: '+(& $encode $row.Identity)+'</p><p>'+(& $encode $row.Detail)+'</p><p>Baseline link/connection: '+(& $encode ($row.BeforeContext.LinkState+' / '+(@($row.BeforeContext.ConnectionState) -join ', ')))+'</p><p>Current link/connection: '+(& $encode ($row.AfterContext.LinkState+' / '+(@($row.AfterContext.ConnectionState) -join ', ')))+'</p>')
        $null=$html.Append('<p>Availability: '+(& $encode ($row.BeforeAvailability+' -> '+$row.AfterAvailability))+'</p>'+(ConvertTo-ContextLink $row.BeforeReference 'Baseline adapter evidence')+' '+(ConvertTo-ContextLink $row.AfterReference 'Current adapter evidence')+' '+(ConvertTo-ContextLink $row.BeforeInventoryReference 'Baseline inventory coverage')+' '+(ConvertTo-ContextLink $row.AfterInventoryReference 'Current inventory coverage')+'</details></td></tr>')
    }
    $null=$html.Append('</table>');$html.ToString()
}

function ConvertTo-InterfaceContextHtml {
    param($Interface,[string]$Path)
    $html=[Text.StringBuilder]::new();$encode={param($x)[Net.WebUtility]::HtmlEncode([string]$x)}
    $null=$html.Append('<section id="'+(Get-ContextAnchor $Path)+'"><h3>'+(& $encode ("$($Interface.Alias) (interface $($Interface.InterfaceIndex))"))+'</h3><p>'+(& $encode $Interface.ConfigurationNote)+'</p><dl>')
    foreach($field in @('StableIdentity','Description','Kind','SelectedDhcpServerState','LeaseReferenceTime','LeaseRemainingSeconds')){$null=$html.Append('<dt>'+$field+'</dt><dd>'+(& $encode $Interface.$field)+'</dd>')}
    foreach($p in $Interface.Values.PSObject.Properties){$null=$html.Append('<dt>'+(& $encode $p.Name)+'</dt><dd>'+(& $encode ((@($p.Value) -join ', ')+' ['+$Interface.Availability.($p.Name)+']'))+'</dd>')}
    $null=$html.Append('</dl><details><summary>Provenance and availability</summary>')
    foreach($p in $Interface.Sources.PSObject.Properties){
        $source=$p.Value
        $null=$html.Append('<p>'+(& $encode ($source.Scope+' '+$source.CheckName+': '+$source.Status+'; '+$source.StartedAt+' to '+$source.CompletedAt))+' ')
        foreach($ref in @($source.EvidenceReferences)+@($source.CheckReferences)){$null=$html.Append((ConvertTo-ContextLink ([pscustomobject]@{Path=$ref}) $ref)+' ')}
        $null=$html.Append('</p>')
    }
    $null=$html.Append('<p>'+(& $encode $Interface.LeaseTimeNote)+'</p></details></section>');$html.ToString()
}

function ConvertTo-DhcpContextHtml {
    param($Evidence)
    $html=[Text.StringBuilder]::new();$encode={param($x)[Net.WebUtility]::HtmlEncode([string]$x)}
    $null=$html.Append('<h2>Per-interface DHCP configuration</h2><p>Competing DHCP servers: not assessed. One selected server and successful client probes do not establish that only one DHCP server exists. Gateways and DNS are configured values; their DHCP origin is not established.</p>')
    for($i=0;$i -lt @($Evidence.DhcpSummary.Interfaces).Count;$i++){$null=$html.Append((ConvertTo-InterfaceContextHtml $Evidence.DhcpSummary.Interfaces[$i] ('/DhcpSummary/Interfaces/'+$i)))}
    $comparison=$Evidence.SnapshotComparison
    $null=$html.Append('<h2>Snapshot comparison</h2><p>'+(& $encode $comparison.Status)+'</p>')
    foreach($side in @('BaselineIdentity','CurrentIdentity')){
        $identity=$comparison.$side
        if($identity){$null=$html.Append('<p>'+(& $encode ($side+': '+$identity.ComputerName+' / '+$identity.RunId+'; '+(Format-ContextTimestamp $identity.StartedAt)+' to '+(Format-ContextTimestamp $identity.CompletedAt)+'; '+$identity.CollectionStatus))+'</p>')}
    }
    if($comparison.Error){$null=$html.Append('<p>'+(& $encode (ConvertTo-Json $comparison.Error -Compress))+'</p>')}
    $null=$html.Append('<p>Two snapshots do not establish continuous health. Lease refreshed is not a captured renewal exchange. Missing evidence limits assessment.</p>')
    if($comparison.Counts){
        $null=$html.Append('<p>'+(& $encode ("Changed: $($comparison.Counts.Changed); lease refreshed: $($comparison.Counts.LeaseRefreshed); unchanged: $($comparison.Counts.Unchanged); not assessed: $($comparison.Counts.NotAssessed)."))+'</p>')
        if($comparison.Counts.Changed -eq 0){$null=$html.Append('<p>No assessed configuration changes. Review lease refreshes and coverage limitations below.</p>')}
    }
    $important=@($comparison.Changes | Where-Object Outcome -in @('Changed','Appeared','Disappeared','Lease refreshed') | Sort-Object @{Expression={if($_.Outcome -eq 'Lease refreshed'){1}else{0}}})
    if($important.Count){$null=$html.Append((ConvertTo-ComparisonRowsHtml $important))}
    foreach($outcome in @('Unchanged','Not assessed')){
        $rows=@($comparison.Changes | Where-Object Outcome -eq $outcome)
        $null=$html.Append('<details><summary>'+(& $encode ($outcome+' ('+$rows.Count+')'))+'</summary>'+(ConvertTo-ComparisonRowsHtml $rows)+'</details>')
    }
    $null=$html.Append('<h2>Supplied configuration expectations</h2><p>A mismatch means outside supplied expectations, not a rogue server or proven root cause.</p><pre>'+(& $encode (ConvertTo-Json $Evidence.ExpectationAssessment -Depth 14))+'</pre><h2>Historical event context</h2><p>Age does not establish relevance or cause. Baseline matches refer to that snapshot, not proven identity at event time.</p>')
    foreach($event in $Evidence.HistoricalEventContext){
        $time=Format-ContextTimestamp $event.EventTime
        $null=$html.Append('<article><h3>'+(& $encode ($time+' | event '+$event.EventId+' | '+$event.Provider))+'</h3><p>'+(& $encode $event.Description)+'</p><p>'+(& $encode (Format-ContextAge $event.AgeSeconds))+'</p><p>'+(& $encode $event.CorrelationSummary)+'</p>')
        foreach($reason in $event.AssessmentReasons){$null=$html.Append('<p>'+(& $encode ($reason.ReasonCode+': '+$reason.Reason))+'</p>')}
        $null=$html.Append('<details><summary>Identifiers, provenance and raw evidence</summary>')
        $null=$html.Append((ConvertTo-ContextLink ([pscustomobject]@{Path=$event.EvidenceReference}) 'Current raw event (message and XML)'))
        foreach($correlation in $event.Correlations){foreach($ref in @($correlation.CurrentMatches)+@($correlation.HistoricalMatches)){$null=$html.Append(' '+(ConvertTo-ContextLink $ref ($ref.Scope+' adapter evidence; run '+$ref.RunId)))}}
        $null=$html.Append('<pre>'+(& $encode (ConvertTo-Json $event -Depth 12))+'</pre></details></article>')
    }
    $baseline=$Evidence.ContextEvidence.Baseline
    if($baseline){
        $null=$html.Append('<h2>Retained baseline evidence</h2><p>'+(& $encode ($baseline.Identity.ComputerName+' / '+$baseline.Identity.RunId+'; '+$baseline.Identity.StartedAt))+'</p><p>Only the six relevant check families are retained. No nested baseline history is imported.</p>')
        for($i=0;$i -lt @($baseline.Interfaces).Count;$i++){$null=$html.Append('<details><summary>'+(& $encode ($baseline.Interfaces[$i].Alias+' baseline adapter'))+'</summary>'+(ConvertTo-InterfaceContextHtml $baseline.Interfaces[$i] ('/ContextEvidence/Baseline/Interfaces/'+$i))+'</details>')}
        for($i=0;$i -lt @($baseline.Checks).Count;$i++){$null=$html.Append('<details id="'+(Get-ContextAnchor ('/ContextEvidence/Baseline/Checks/'+$i))+'"><summary>'+(& $encode ($baseline.Checks[$i].Name+': '+$baseline.Checks[$i].Status))+'</summary><pre>'+(& $encode (ConvertTo-Json $baseline.Checks[$i] -Depth 14))+'</pre></details>')}
    }
    $html.ToString()
}
