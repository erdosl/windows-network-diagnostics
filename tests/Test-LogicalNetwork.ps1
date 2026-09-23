#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core.ps1','State.ps1','Collection.ps1','Events.ps1','Connectivity.ps1','Orchestration.ps1')) { . (Join-Path $root "src\$file") }
$script:count=0
function Assert-Map { param($Condition,$Message); if (-not $Condition) { throw "Assertion failed: $Message" }; $script:count++ }
function Check { param($Name,$Data); [pscustomobject]@{Name=$Name;Status='Success';StartedAt='2026-01-01T00:00:00+00:00';CompletedAt='2026-01-01T00:00:01+00:00';Data=@($Data)} }
$adapters=@([pscustomobject]@{InterfaceIndex=7;Name='Ethernet <script>';HardwareInterface=$true},[pscustomobject]@{InterfaceIndex=8;Name='Wi-Fi synthetic';HardwareInterface=$true})
$addresses=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.10';PrefixLength=24},[pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.11';PrefixLength=24},[pscustomobject]@{InterfaceIndex=8;IPAddress='192.0.2.10';PrefixLength=24},[pscustomobject]@{InterfaceIndex=8;IPAddress='192.0.2.20';PrefixLength=25},[pscustomobject]@{InterfaceIndex=7;IPAddress='fe80::10%7';PrefixLength=64})
$routes=@([pscustomobject]@{InterfaceIndex=7;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.1';RouteMetric=5},[pscustomobject]@{InterfaceIndex=7;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.2';RouteMetric=10},[pscustomobject]@{InterfaceIndex=8;DestinationPrefix='::/0';NextHop='fe80::1%8'})
$neighbours=@()
foreach ($spec in @(@(7,'192.0.2.1','02-00-00-00-00-01',4),@(8,'192.0.2.1','02-00-00-00-00-02',5),@(7,'192.0.2.2','02-00-00-00-00-01',0),@(7,'192.0.2.3','00-00-00-00-00-00',1),@(7,'fe80::1%7','02-00-00-00-00-03',6),@(8,'fe80::1%8','02-00-00-00-00-03',42),@(7,'192.0.2.255','ff-ff-ff-ff-ff-ff',6),@(7,'224.0.0.1','01-00-5e-00-00-01',6),@(7,'ff02::1%7','33-33-00-00-00-01',6),@(7,'255.255.255.255','ff-ff-ff-ff-ff-ff',6))) {
    $neighbours += [pscustomobject]@{InterfaceIndex=$spec[0];IPAddress=$spec[1];LinkLayerAddress=$spec[2];State=$spec[3]}
}
$probe=[pscustomobject]@{Destination='203.0.113.9';RoutePrediction=[pscustomobject]@{Routes=@($routes[0])};ObservedConnection=[pscustomobject]@{LocalAddress='192.0.2.10';RemoteAddress='203.0.113.9';InterfaceMatches=@([pscustomobject]@{InterfaceIndex=7})}}
$e=[pscustomobject]@{ComputerName='Synthetic <computer>';StartedAt='2026-01-01T00:00:00+00:00';CompletedAt='2026-01-01T00:00:02+00:00';Checks=@((Check Adapters $adapters),(Check IPAddresses $addresses),(Check Routes $routes),(Check Neighbours $neighbours),(Check 'Connectivity:TCP:synthetic' $probe));Findings=[pscustomobject]@{Observations=@();Hypotheses=@()}}
$original=ConvertTo-Json $e -Depth 24
$m=Get-LogicalNetworkModel $e
Assert-Map ($m.Counts.Interfaces -eq 2) 'Separate physical interfaces'
Assert-Map ($m.Counts.Subnets -eq 4) 'Prefixes deduplicated only within same interface/scope; overlaps preserved'
Assert-Map (@($m.Nodes | Where-Object Kind -eq Address).Count -eq 5) 'Multiple assigned addresses retained'
Assert-Map (@($m.Nodes | Where-Object Kind -eq Gateway).Count -eq 3) 'Multiple candidate gateways retained'
Assert-Map ($m.Counts.NeighbourObservations -eq 10 -and $m.Counts.EligibleEndpointObservations -eq 5) 'Broadcast/multicast and missing MAC filtered only from endpoint observation count'
$n=@($m.Nodes | Where-Object Kind -eq NeighbourObservation)
Assert-Map (@($n | Where-Object {$_.Data.IPAddress -eq '192.0.2.1'}).Count -eq 2) 'Same IP different interfaces/MACs not merged'
Assert-Map (@($n | Where-Object {$_.Data.LinkLayerAddress -eq '02-00-00-00-00-01'}).Count -eq 2) 'Same MAC multiple IPs not merged'
Assert-Map (@($n | Where-Object {$_.Data.IPAddress -like 'fe80::*'}).Count -eq 2) 'IPv6 zone context retained'
foreach ($state in @('Stale','Incomplete','Unreachable','Permanent','Unknown (42)')) { Assert-Map (@($n | Where-Object {$_.Data.StateLabel -eq $state}).Count -gt 0) "Readable state $state" }
Assert-Map ($n[0].Data.StateRaw -eq 4) 'Raw state preserved'
Assert-Map (@($m.Nodes | Where-Object Kind -eq ObservedSocket).Count -eq 1 -and @($m.Nodes | Where-Object {$_.Kind -eq 'Gateway' -and $_.Label -eq '203.0.113.9'}).Count -eq 0) 'Remote socket is never gateway identity'
Assert-Map (@($m.Nodes | Where-Object {$_.Kind -eq 'RoutePrediction' -and $_.Support[0].EvidenceType -eq 'predicted'}).Count -eq 1) 'Predictions distinct from observations'
foreach ($item in @($m.Nodes)+@($m.Relationships)) { Assert-Map ($item.Id -and $item.Support[0].CheckName -and $item.Support[0].EvidenceReference -and $item.Support[0].StartedAt -and $item.Support[0].Limitation) 'Every graph item has provenance, time and limitations' }
Assert-Map ((ConvertTo-Json $m -Depth 24) -eq (ConvertTo-Json (Get-LogicalNetworkModel $e) -Depth 24)) 'Deterministic generation'
Assert-Map ((ConvertTo-Json $e -Depth 24) -eq $original) 'Input raw evidence unchanged'
$configuredOnly=Get-LogicalNetworkModel ([pscustomobject]@{Checks=@((Check DHCPAndGateways @([pscustomobject]@{InterfaceIndex=9;DefaultIPGateway=@('198.51.100.1')})))})
Assert-Map (@($configuredOnly.Nodes | Where-Object Kind -eq Gateway).Count -eq 1) 'Configured gateway preserved when route source is absent'
Assert-Map (@($m.Relationships | Where-Object {$_.Kind -eq 'PredictedInterfaceCandidate' -and $_.Support[0].EvidenceType -eq 'predicted'}).Count -gt 0) 'Predicted interface associations are explicitly predicted'
$missing=Get-LogicalNetworkModel ([pscustomobject]@{Checks=@([pscustomobject]@{Name='Neighbours';Status='Failed';Data=@()})})
Assert-Map (@($missing.Coverage | Where-Object {$_.Source -eq 'Neighbours' -and $_.Status -eq 'Failed'}).Count -eq 1) 'Failed sources visible'
Assert-Map (@($missing.Coverage | Where-Object Status -eq NotCollected).Count -gt 0) 'Missing sources visible'
$e.Checks[3].Data += [pscustomobject]@{InterfaceIndex=7;IPAddress='<img src=x>';LinkLayerAddress='<mac>';State='<state>'}
$workspace=Join-Path $root ('output\tests\map-'+[guid]::NewGuid().ToString('N'))
$paths=Write-DiagnosticReport $e $workspace
$html=Get-Content -Raw $paths.HtmlPath
Assert-Map ($html.Contains('&lt;script&gt;') -and $html.Contains('&lt;img src=x&gt;') -and $html.Contains('&lt;state&gt;') -and -not $html.Contains('<img src=x>')) 'Hostile map fields encoded'
Assert-Map ($html.Contains('<details>') -and $html.Contains('Unknown Layer 2')) 'Collapsible neighbour lists and unknown physical paths'
# Per-adapter isolation is in the parent: each provider call gets its own bounded worker.
function Get-NetAdapterStatistics { [CmdletBinding()]param($Name,[switch]$IncludeHidden); [pscustomobject]@{Name='good';ReceivedBytes=123;ReceivedPacketErrors=9} }
function Get-NetAdapterPowerManagement { [CmdletBinding()]param($Name,[switch]$IncludeHidden); if($script:denyPower){throw [UnauthorizedAccessException]::new('Synthetic denied')}; [pscustomobject]@{Name='good';WakeOnMagicPacket=1} }
$good=Invoke-DiagnosticCheck 'stats' { Invoke-AdapterDetail AdapterStatistics 'good' 7 'synthetic-guid' }
$bad=Invoke-DiagnosticCheck 'stats-bad' { Invoke-AdapterDetail AdapterStatistics 'unsupported' 8 '' }
$power=Invoke-DiagnosticCheck 'power' { Invoke-AdapterDetail AdapterPowerManagement 'good' 7 '' }
$script:denyPower=$true
$denied=Invoke-DiagnosticCheck 'power-bad' { Invoke-AdapterDetail AdapterPowerManagement 'denied' 8 '' }
Assert-Map ($good.Status -eq 'Success' -and $good.Data[0].Fields.ReceivedBytes -eq 123 -and $good.Data[0].StartedAt -and $good.Data[0].Limitation -match 'not a rate') 'Supported counters with identifiers/time and cumulative warning'
Assert-Map ($bad.Status -eq 'Unavailable' -and $power.Status -eq 'Success' -and $denied.Status -eq 'PermissionDenied') 'Adapter statistics/power partial availability'
# Full scheduling test with mocked persistence/execution, no live collection.
function Write-DiagnosticReport {param($Evidence,$OutputDirectory)}
$script:details=@()
$executor={param($definition,$timeout,$directory)
    if($definition.FunctionName -eq 'Invoke-AdapterDetail'){ $script:details += $definition; Assert-Map ($timeout -eq 3) 'Each adapter gets bounded passive budget' }
    $data=@(); if($definition.Name -eq 'Adapters'){$data=$adapters}
    [pscustomobject]@{Name=$definition.Name;Status=$(if($definition.Name -eq 'AdapterStatistics:7'){'Unavailable'}else{'Success'});Data=$data}
}
$run=Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $workspace -CheckExecutor $executor -CheckTimeoutSeconds 3
Assert-Map ($script:details.Count -eq 4 -and $run.Evidence.CollectionStatus -eq 'Complete') 'Independent per-adapter checks continue after failure'
Assert-Map (($run.Evidence.Checks | Where-Object Name -eq Connectivity).Status -eq 'Skipped') 'Map adds no active traffic'
Write-Host "PASS: $script:count logical-map assertions."
