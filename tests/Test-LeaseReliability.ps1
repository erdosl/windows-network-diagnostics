#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1');. (Join-Path $root 'src\Observation.ps1');. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$count=0
function Assert($ok,$message){if(-not $ok){throw $message};$script:count++}
$a='2026-01-01T09:00:00Z'
foreach($case in @(@('2026-01-01T10:00:00+01:00','SameInstant','Unchanged'),@('2026-01-01T10:00:00Z','ForwardProgression','LeaseRefreshed'),@('2026-01-01T08:00:00Z','BackwardMovement','Changed'),@($null,'Cleared','Changed'),@('bad','InvalidTimestamp','Not assessed'))){
    $result=Compare-LeaseTimestamp $a $case[0]
    Assert ($result.Classification -eq $case[1] -and $result.Outcome -eq $case[2]) 'Precise lease classification'
    $before=New-DhcpReviewFixture;$after=New-DhcpReviewFixture
    $before.Checks[1].Data[0].DHCPLeaseObtained=$a;$after.Checks[1].Data[0].DHCPLeaseObtained=$case[0]
    $change=Compare-ObservationDhcpState (Get-ObservationDhcpState $before.Checks) (Get-ObservationDhcpState $after.Checks)
    Assert ($change.Outcome -eq $case[2]) 'Observation uses shared instant semantics'
    $baseline=[pscustomobject]@{Identity=$before | Select-Object ComputerName,RunId,StartedAt,CollectionStatus;Checks=$before.Checks;Interfaces=@(Get-DhcpInterfaceContext $before);AdapterInventoryStatus='Success'}
    $snapshot=Compare-DhcpContext @(Get-DhcpInterfaceContext $after) $baseline $after
    $row=@($snapshot.Changes | Where-Object {$_.Field -eq 'LeaseObtained' -and $_.Identity -eq '11111111-1111-1111-1111-000000000001'})[0]
    Assert ($row.LeaseTimestamp.Classification -eq $case[1]) 'Snapshot uses same lease classification and raw timestamps'
}
$before=New-DhcpReviewFixture;$after=New-DhcpReviewFixture
$after.Checks[1].Data[0].PSObject.Properties.Remove('DHCPLeaseExpires');$after.Checks[1].Data[0].DHCPServer='192.0.2.9'
$change=Compare-ObservationDhcpState (Get-ObservationDhcpState $before.Checks) (Get-ObservationDhcpState $after.Checks)
Assert ($change.Outcome -eq 'Changed' -and $change.Coverage -eq 'Partial') 'Assessed change survives missing lease coverage'
Assert (@($change.ChangedFields | Where-Object Field -eq DHCPServer).Count -eq 1) 'Changed field retained'
Assert (@($change.Reasons | Where-Object Code -eq MissingProperty).Count -gt 0) 'Missing property stays explicit'
$after.Checks[0].Data[0].InterfaceGuid=$after.Checks[0].Data[1].InterfaceGuid
$ambiguous=Compare-ObservationDhcpState (Get-ObservationDhcpState $before.Checks) (Get-ObservationDhcpState $after.Checks)
Assert (@($ambiguous.Reasons | Where-Object Code -match 'Identity|Inventory').Count -gt 0) 'Conflicting identities retain unassessed coverage'
$before.Checks[-1] | Add-Member NoteProperty StartedAt '2026-01-01T07:00:00Z'
$before.Checks[-1] | Add-Member NoteProperty CompletedAt '2026-01-01T09:00:00Z'
$events=@(Get-HistoricalEventContext $before @(Get-DhcpInterfaceContext $before) $null)
Assert ($events[0].RawReference.Path -like '/Checks/*/Data/*/Events/*' -and $events[0].Correlations[0].Confidence -eq 'Current exact identifier match') 'Structured event association preserves scoped raw references'
Assert ($events[0].Note -match 'not a current fault diagnosis' -and $events[0].SourceStartedAt) 'Event interval and noncausal limitation retained'
Write-Host "PASS: $count lease reliability assertions."
