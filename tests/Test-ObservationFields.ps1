#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1');. (Join-Path $root 'src\Observation.ps1')
function Assert($v,$m){if(-not $v){throw $m}}
function Fixture($index){@([pscustomobject]@{Name='Adapters';Status='Success';Data=@([pscustomobject]@{InterfaceGuid='11111111-1111-1111-1111-111111111111';InterfaceIndex=$index;Status='Up'})},[pscustomobject]@{Name='IPAddresses';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=$index;IPAddress='2001:db8::1';PrefixLength=64;AddressState=4},[pscustomobject]@{InterfaceIndex=$index;IPAddress='192.0.2.1';PrefixLength=24;AddressState=4})},[pscustomobject]@{Name='DNSServers';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=$index;AddressFamily=2;ServerAddresses=@('192.0.2.53','192.0.2.54')})})}
$a=Fixture 1;$b=Fixture 9;$b[1].Data=@($b[1].Data[1],$b[1].Data[0]);$b[1].Data[1].IPAddress='2001:0db8:0:0:0:0:0:1'
function CompareFixture($name,$status='Complete'){Compare-ObservationFields (Get-ObservationFieldState $a $name Complete) (Get-ObservationFieldState $b $name $status) $name 'sample-0000.json' 'sample-0001.json'}
Assert ((CompareFixture IPAddresses).Outcome -eq 'Unchanged') 'Index churn, address spelling or record order created a change'
$b[1].Data[0].PrefixLength=25;$r=CompareFixture IPAddresses;Assert ($r.ChangedFields[0].Field -eq 'PrefixLength' -and $r.ChangedFields[0].Before -eq 24) 'Prefix difference missing'
$b[2].Data[0].ServerAddresses=@('192.0.2.54','192.0.2.53');Assert ((CompareFixture DNSServers).ChangedFields[0].Field -eq 'ServerAddresses') 'DNS priority order lost'
$b[1].Data=@();Assert ((CompareFixture IPAddresses).ChangedFields.Count -eq 2) 'Complete empty source must retain assessed removals'
Assert ((CompareFixture IPAddresses Incomplete).Outcome -eq 'Not assessed') 'Partial source manufactured removals'
$b=Fixture 9;$b[0].Data+= $b[0].Data[0];Assert ((CompareFixture IPAddresses).Outcome -eq 'Not assessed') 'Ambiguous inventory matched'
$a=Fixture 1;$b=Fixture 9
$b[0].Data+=[pscustomobject]@{InterfaceGuid=$b[0].Data[0].InterfaceGuid;InterfaceIndex=10;Status='Up'}
$b[1].Data[0].PrefixLength=48
Assert ((CompareFixture IPAddresses).Outcome -eq 'Not assessed') 'Duplicate GUID on distinct indices manufactured a change'
foreach($checks in @($a,$b)){
    $checks[0].Data+=[pscustomobject]@{InterfaceGuid='22222222-2222-2222-2222-222222222222';InterfaceIndex=20;Status='Up'}
    $checks[1].Data+=[pscustomobject]@{InterfaceIndex=20;IPAddress='192.0.2.20';PrefixLength=24;AddressState=4}
}
$b[1].Data[-1].PrefixLength=25;$r=CompareFixture IPAddresses
Assert ($r.Coverage -eq 'Partial' -and $r.ChangedFields.Count -eq 1 -and $r.ChangedFields[0].Identity -eq '22222222-2222-2222-2222-222222222222') 'Ambiguous GUID suppressed or contaminated an unrelated unique identity'
$b=Fixture 9;$b[1].Data[0].PSObject.Properties.Remove('PrefixLength');Assert ((CompareFixture IPAddresses).Coverage -eq 'Partial') 'Missing property suppressed'
$a=Fixture 1;$b=Fixture 9
$a+=[pscustomobject]@{Name='Routes';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=1;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=10;InterfaceMetric=5})}
$b+=[pscustomobject]@{Name='Routes';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=9;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=20;InterfaceMetric=5})}
Assert ((CompareFixture Routes).ChangedFields[0].Field -eq 'RouteMetric') 'Route metric change missing'
$b[0].Data[0].Status='Disconnected';Assert ((CompareFixture Adapters).ChangedFields[0].Field -eq 'Status') 'Link change missing'
$b[1].Data+= [pscustomobject]@{InterfaceIndex=9;IPAddress='192.0.2.99';PrefixLength=24;AddressState='Preferred'}
Assert (@((CompareFixture IPAddresses).ChangedFields | Where-Object Outcome -eq 'Added').Count -eq 1) 'Added record not assessed'
Write-Host 'PASS: stable identity field changes, DNS order, equivalent address/order/index representations, incomplete/ambiguous coverage.'
