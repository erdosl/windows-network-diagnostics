#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\State.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$script:passed=0;$script:failed=0
function Check {param($Condition,$Message);if($Condition){$script:passed++;Write-Host "PASS: $Message"}else{$script:failed++;Write-Host "FAIL: $Message"}}
function Fixture {
    $e=New-DhcpReviewFixture
    $e.Checks=@($e.Checks | Where-Object Name -notlike 'Events:*')
    foreach($c in $e.Checks){$c.Data=@($c.Data | Where-Object InterfaceIndex -eq 1)}
    $e.Checks += [pscustomobject]@{Name='Routes';Status='Success';Data=@();StartedAt=$e.StartedAt;CompletedAt=$e.CompletedAt}
    $e.Checks += [pscustomobject]@{Name='DNSServers';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=1;AddressFamily=2;ServerAddresses=@('192.0.2.53')});StartedAt=$e.StartedAt;CompletedAt=$e.CompletedAt}
    $e
}
function Baseline {param($e);[pscustomobject]@{Identity=($e | Select-Object RunId,ComputerName,CollectionStatus,StartedAt,CompletedAt);AdapterInventoryStatus=@($e.Checks | Where-Object Name -eq 'Adapters')[0].Status;Checks=$e.Checks;Interfaces=@(Get-DhcpInterfaceContext $e Baseline '/ContextEvidence/Baseline')}}
function Compare-SyntheticSnapshot {param($old,$now);Compare-DhcpContext @(Get-DhcpInterfaceContext $now) (Baseline $old) $now}
function Field {param($comparison,$field);@($comparison.Changes | Where-Object {$_.Field -eq $field -and $_.Identity -eq '11111111-1111-1111-1111-000000000001'})[0]}
function Loopback {param($e);$e.Checks[2].Data += [pscustomobject]@{InterfaceIndex=99;IPAddress='127.0.0.1';PrefixLength=8;AddressFamily=2}}
function Empty {param($e,$field)
    switch($field){
        IPv4 {$e.Checks[2].Data=@()}
        Gateways {$e.Checks[1].Data[0].DefaultIPGateway=@();($e.Checks | Where-Object Name -eq 'Routes').Data=@()}
        DnsServers {$e.Checks[1].Data[0].DNSServerSearchOrder=@();($e.Checks | Where-Object Name -eq 'DNSServers').Data[0].ServerAddresses=@()}
    }
}
$old=Fixture;$now=Fixture
foreach($c in $old.Checks){$c.Data=@()};Loopback $old;Loopback $now
Check ((Field (Compare-SyntheticSnapshot $old $now) Adapter).Outcome -eq 'Appeared') 'Stable adapter appeared despite opposite IP-only loopback'
Check ((Field (Compare-SyntheticSnapshot $now $old) Adapter).Outcome -eq 'Disappeared') 'Stable adapter disappeared despite opposite IP-only loopback'
$old.Checks[0].Status='Unavailable'
Check ((Field (Compare-SyntheticSnapshot $old $now) Adapter).Outcome -eq 'Not assessed') 'Unavailable opposite inventory remains uncertain'
$old.Checks[0].Status='Success';$old.CollectionStatus='Incomplete'
Check ((Field (Compare-SyntheticSnapshot $old $now) Adapter).Outcome -eq 'Not assessed') 'Incomplete opposite snapshot remains uncertain'
$old=Fixture;$old.Checks[0].Data[0].InterfaceGuid=$null;$old.Checks[1].Data[0].SettingID=$null
$row=Field (Compare-SyntheticSnapshot $old $now) Adapter
Check ($row.Outcome -eq 'Not assessed' -and [bool]$row.Detail) 'Inventoried adapter without stable identity prevents absence with reason'
$old=Fixture;$old.Checks[1].Data[0].SettingID='22222222-2222-2222-2222-222222222222'
Check ((Field (Compare-SyntheticSnapshot $old $now) Adapter).Outcome -eq 'Not assessed') 'Conflicting inventory identities remain uncertain'
$old=Fixture;$old.Checks[0].Data += $old.Checks[0].Data[0]
Check ((Field (Compare-SyntheticSnapshot $old $now) Adapter).Outcome -eq 'Not assessed') 'Duplicate inventory records remain ambiguous'
$old=Fixture;$now=Fixture
Check ((Field (Compare-SyntheticSnapshot $old $now) MacAddress).Outcome -eq 'Unchanged') 'Unchanged adapter configuration stays unchanged'
foreach($name in @('IPv4','Gateways','DnsServers')){
    $old=Fixture;$now=Fixture;Empty $now $name
    $row=Field (Compare-SyntheticSnapshot $old $now) $name
    Check ($row.Outcome -eq 'Changed' -and @($row.After).Count -eq 0) "$name last value removal assessed"
    Check ((Field (Compare-SyntheticSnapshot $now $old) $name).Outcome -eq 'Changed') "$name empty-to-populated assessed"
    Check ((Field (Compare-SyntheticSnapshot $now $now) $name).Outcome -eq 'Unchanged') "$name observed empty-to-empty unchanged"
    Check ($row.StateNote -eq 'Retained configuration changed on a disconnected adapter.') "$name removal retains disconnected state context"
    $source=$(if($name -eq 'IPv4'){'IPAddresses'}elseif($name -eq 'Gateways'){'Routes'}else{'DNSServers'})
    ($now.Checks | Where-Object Name -eq $source).Status='Unavailable'
    Check ((Field (Compare-SyntheticSnapshot $old $now) $name).Outcome -eq 'Not assessed') "$name unavailable empty coverage unassessed"
    $now.Checks=@($now.Checks | Where-Object Name -ne $source)
    Check ((Field (Compare-SyntheticSnapshot $old $now) $name).Outcome -eq 'Not assessed') "$name uncollected empty coverage unassessed"
    $now=Fixture;Empty $now $name;$now.CollectionStatus='Incomplete'
    Check ((Field (Compare-SyntheticSnapshot $old $now) $name).Outcome -eq 'Not assessed') "$name incomplete empty coverage unassessed"
}
$old=Fixture;$now=Fixture;$now.Checks[1].Data[0].DefaultIPGateway=$null
($now.Checks | Where-Object Name -eq 'Routes').Data=@([pscustomobject]@{InterfaceIndex=1;DestinationPrefix='0.0.0.0/0';NextHop='198.51.100.1'})
$i=@(Get-DhcpInterfaceContext $now)[0]
Check ($i.Values.Gateways[0] -eq '198.51.100.1' -and $i.GatewayValueSource -eq 'Routes') 'Gateway fallback retains value and source'
$now.Checks[1].Data[0].DNSServerSearchOrder=$null
$i=@(Get-DhcpInterfaceContext $now)[0]
Check ($i.Values.DnsServers[0] -eq '192.0.2.53' -and $i.DnsValueSource -eq 'DNSServers') 'DNS fallback retains value and source'
$now=Fixture;Empty $now DnsServers;($now.Checks | Where-Object Name -eq 'DNSServers').Data=@()
Check ((Field (Compare-SyntheticSnapshot $old $now) DnsServers).Outcome -eq 'Not assessed') 'No DNS interface record is not proof of emptiness'
$now=Fixture;Empty $now Gateways;$now.Checks[1].Data += $now.Checks[1].Data[0]
Check ((Field (Compare-SyntheticSnapshot $old $now) Gateways).Outcome -eq 'Not assessed') 'Ambiguous primary configuration cannot establish empty gateway list'
$now=Fixture;Empty $now DnsServers;($now.Checks | Where-Object Name -eq 'DNSServers').Data[0].ServerAddresses=$null
Check ((Field (Compare-SyntheticSnapshot $old $now) DnsServers).Outcome -eq 'Not assessed') 'Null DNS list not explicit empty enumeration'
$old=Fixture;$old.Checks[2].Data += [pscustomobject]@{InterfaceIndex=1;IPAddress='198.51.100.41';PrefixLength=24;AddressFamily=2}
$now=Fixture;$now.Checks[2].Data=@($old.Checks[2].Data[1],$old.Checks[2].Data[0])
Check ((Field (Compare-SyntheticSnapshot $old $now) IPv4).Outcome -eq 'Unchanged') 'IPv4 reordering ignored'
$now=Fixture;Empty $now Gateways;Empty $now DnsServers;$now.Checks[0].Data[0].Status='Up';$now.Checks[3].Data[0].ConnectionState=1
$rules=[pscustomobject]@{Defaults=[pscustomobject]@{AllowedGateways=@('198.51.100.1');DnsServers=@('198.51.100.53')};Interfaces=@()}
Check (@(Test-DhcpExpectations @(Get-DhcpInterfaceContext $now) $rules | Where-Object Outcome -eq 'Mismatch').Count -eq 0) 'Observed empty does not become expectation mismatch'
$old=Fixture;$now=Fixture
foreach($c in $old.Checks){$c.Data=@()};Loopback $old;Loopback $now
$appeared=Field (Compare-SyntheticSnapshot $old $now) Adapter
$removed=Field (Compare-SyntheticSnapshot $now $old) Adapter
Check ($appeared.AfterReference.Scope -eq 'Current' -and $removed.BeforeReference.Scope -eq 'Baseline') 'Presence rows retain scoped adapter references'
Check ($appeared.AfterContext.InterfaceIndex -eq 1 -and $removed.BeforeContext.LinkState -eq 'Disconnected') 'Presence rows retain before/after state'
$old=Fixture;$now=Fixture;Empty $now Gateways;$now.Checks[1].Data[0].DefaultIPGateway=$null
Check ((Field (Compare-SyntheticSnapshot $old $now) Gateways).Outcome -eq 'Changed') 'Null primary plus complete empty route enumeration establishes no effective gateway'
($now.Checks | Where-Object Name -eq 'Routes').Status='Unavailable'
Check ((Field (Compare-SyntheticSnapshot $old $now) Gateways).Outcome -eq 'Not assessed') 'Null primary alone never establishes empty gateways'
$now=Fixture;Empty $now DnsServers;$now.Checks[1].Data[0].DNSServerSearchOrder=$null
Check ((Field (Compare-SyntheticSnapshot $old $now) DnsServers).Outcome -eq 'Changed') 'Null primary plus explicit empty DNS provider list establishes effective emptiness'
$now=Fixture;Empty $now Gateways;$now.Checks[1].Data=@()
Check ((Field (Compare-SyntheticSnapshot $old $now) Gateways).Outcome -eq 'Not assessed') 'Missing primary interface record does not establish empty configuration'
foreach($field in @('IPv4','Gateways','DnsServers')){
    $now=Fixture
    switch($field){
        IPv4 {$now.Checks[2].Data[0].IPAddress=$null}
        Gateways {$now.Checks[1].Data[0].DefaultIPGateway=@('invalid')}
        DnsServers {$now.Checks[1].Data[0].DNSServerSearchOrder=@('invalid')}
    }
    Check ((Field (Compare-SyntheticSnapshot $old $now) $field).Outcome -eq 'Not assessed') "$field invalid values not assessed"
}
$now=Fixture;Empty $now IPv4;$now.Checks += $now.Checks[2]
Check ((Field (Compare-SyntheticSnapshot $old $now) IPv4).Outcome -eq 'Not assessed') 'Duplicate source checks cannot establish empty enumeration'
$now=Fixture;Empty $now DnsServers
$dns=$now.Checks | Where-Object Name -eq 'DNSServers';$dns.Data += $dns.Data[0]
Check ((Field (Compare-SyntheticSnapshot $old $now) DnsServers).Outcome -eq 'Not assessed') 'Duplicate DNS family records cannot establish empty list'
$now=Fixture;Empty $now IPv4;Empty $now Gateways;Empty $now DnsServers
$context=@(Get-DhcpInterfaceContext $now)[0]
Check ($context.Availability.IPv4 -eq 'ObservedEmpty' -and $context.Availability.Gateways -eq 'ObservedEmpty' -and $context.Availability.DnsServers -eq 'ObservedEmpty') 'ObservedEmpty is explicit rather than Available or Missing'
Check ($context.Sources.IPAddresses.CheckReferences[0] -eq '/Checks/2' -and $context.Sources.IPAddresses.EvidenceReferences.Count -eq 0) 'Empty enumeration retains check-level evidence reference'
$work=Join-Path $root ('output\tests\snapshot-comparison-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$paths=Write-DiagnosticReport $now (Join-Path $work 'report')
$saved=Get-Content -LiteralPath $paths.JsonPath -Raw | ConvertFrom-Json
Check ($saved.DhcpSummary.Interfaces[0].Values.IPv4.Count -eq 0 -and $saved.DhcpSummary.Interfaces[0].Values.Gateways.Count -eq 0 -and $saved.DhcpSummary.Interfaces[0].Values.DnsServers.Count -eq 0) 'Observed empty collections round-trip as []'
Check ($saved.ContextEvidence.ContractVersion -eq 4) 'Availability contract change explicitly versioned'
$now.SchemaVersion=7
$now | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath (Join-Path $work 'schema7.json') -Encoding UTF8
$loaded=Read-ContextInput (Join-Path $work 'schema7.json') Baseline SYNTHETIC
Check ($loaded.Interfaces[0].Availability.IPv4 -eq 'ObservedEmpty' -and $loaded.Interfaces[0].Sources.IPAddresses.CheckReferences[0] -eq '/ContextEvidence/Baseline/Checks/2') 'Old schema baseline normalized from raw with scoped empty evidence'
Check ($appeared.BeforeInventoryReference.Path -eq '/ContextEvidence/Baseline/Checks/0' -and $removed.AfterInventoryReference.Path -eq '/Checks/0') 'Absence has scoped raw inventory evidence even without an adapter record'
$old=Fixture;$now=Fixture;Empty $now Gateways
($now.Checks | Where-Object Name -eq 'Routes').Data=@([pscustomobject]@{InterfaceIndex=1;DestinationPrefix='invalid';NextHop=$null})
Check ((Field (Compare-SyntheticSnapshot $old $now) Gateways).Outcome -eq 'Not assessed') 'Malformed route coverage not interpreted as empty gateways'
Write-Host "RESULT: $script:passed passed; $script:failed failed on PowerShell $($PSVersionTable.PSVersion)."
if($script:failed){exit 1}
