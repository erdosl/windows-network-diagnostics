#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
$before=New-DhcpReviewFixture;$after=New-DhcpReviewFixture
$state=Get-ObservationState $before.Checks
$changes=@(Compare-ObservationState $state (Get-ObservationState $after.Checks))
Assert (@($changes | Where-Object Outcome -eq 'Changed').Count -eq 0) 'Unchanged observations'
$after.Checks[0].Data[0].Status='Up'
Assert (@(Compare-ObservationState $state (Get-ObservationState $after.Checks) | Where-Object { $_.Source -eq 'Adapters' -and $_.Outcome -eq 'Changed' }).Count -eq 1) 'Link state change'
$after.Checks[0].Status='Failed'
Assert (@(Compare-ObservationState $state (Get-ObservationState $after.Checks) | Where-Object { $_.Source -eq 'Adapters' -and $_.Outcome -eq 'Not assessed' }).Count -eq 1) 'Failure is not unchanged'
$after=New-DhcpReviewFixture -Current
Assert (@(Compare-ObservationState $state (Get-ObservationState $after.Checks) | Where-Object { $_.Source -eq 'DHCPAndGateways' -and $_.Outcome -eq 'Changed' }).Count -eq 1) 'Gateway changes'
$guid=$before.Checks[0].Data[0].InterfaceGuid
$bstat=[pscustomobject]@{Name='AdapterStatistics:1';Status='Success';Data=@([pscustomobject]@{InterfaceGuid=$guid;Fields=[pscustomobject]@{ReceivedBytes=100}})}
$astat=[pscustomobject]@{Name='AdapterStatistics:1';Status='Success';Data=@([pscustomobject]@{InterfaceGuid=$guid;Fields=[pscustomobject]@{ReceivedBytes=200}})}
$before.Checks+=$bstat;$after.Checks+=$astat
$before.RunId='synthetic-run';$after.RunId='synthetic-run'
$bstat.Data[0] | Add-Member NoteProperty CounterTiming ([pscustomobject]@{RunId='synthetic-run';Basis='SystemStopwatch';StartSeconds=1;EndSeconds=2})
$astat.Data[0] | Add-Member NoteProperty CounterTiming ([pscustomobject]@{RunId='synthetic-run';Basis='SystemStopwatch';StartSeconds=5;EndSeconds=6})
$delta=@(Get-CounterDeltas $before $after 4)[0]
Assert ($delta.Delta -eq 100 -and $delta.PerSecond -eq 25) 'Rate uses actual elapsed seconds'
$astat.Data[0].Fields.ReceivedBytes=50
Assert (@(Get-CounterDeltas $before $after 4)[0].Status -eq 'Discontinuity') 'Counter decrease is reset'
$astat.Data[0].InterfaceGuid='22222222-2222-2222-2222-222222222222'
Assert (@(Get-CounterDeltas $before $after 4)[0].Delta -eq $null) 'Identity change never produces delta'
$astat.Data[0].InterfaceGuid=$guid;$astat.Data[0].Fields.ReceivedBytes=200;$after.Checks[0].Data[0].Status='Up'
Assert (@(Get-CounterDeltas $before $after 4)[0].Status -eq 'Discontinuity') 'Link restart boundary is discontinuity'
Assert (@(Get-CounterDeltas $before $after 0)[0].PerSecond -eq $null) 'No divide by zero'
$group=[pscustomobject]@{LogName='Synthetic';Events=@([pscustomobject]@{RecordId=1;TimeCreated='2026-01-01T00:00:00Z';Xml='<Event />'})}
$seen=@{}
Assert (@(Select-NewObservationEvents $group $seen).Count -eq 1) 'New event retained'
Assert (@(Select-NewObservationEvents $group $seen).Count -eq 0) 'Overlapping event window deduplicated'
$group.LogName='Other'
Assert (@(Select-NewObservationEvents $group $seen).Count -eq 1) 'Event log scope retained'
$group.Events[0].TimeCreated='2026-01-01T00:01:00Z'
Assert (@(Select-NewObservationEvents $group $seen).Count -eq 1) 'Reused record ID with different timestamp retained'
Write-Host "PASS: $script:count observation assertions on $($PSVersionTable.PSVersion)."
