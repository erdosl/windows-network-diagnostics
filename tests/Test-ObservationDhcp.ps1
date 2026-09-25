#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\Observation.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function Compare-DhcpObservation($a,$b){Compare-ObservationState (Get-ObservationState $a.Checks) (Get-ObservationState $b.Checks)|Where-Object Source -eq 'DHCPAndGateways'}
$a=New-DhcpReviewFixture;$b=New-DhcpReviewFixture
$b.Checks[1].Data[0].DHCPServer='192.0.2.9'
$change=Compare-DhcpObservation $a $b
Assert ($change.Outcome -eq 'Changed' -and $change.ChangedFields[0].Field -eq 'DHCPServer') 'Server-only change'
Assert ($change.ChangedFields[0].BeforePath -eq '/Checks/1/Data/0' -and $change.ChangedFields[0].AfterPath -eq '/Checks/1/Data/0') 'Raw record provenance retained'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].DNSDomain='<changed>.example'
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Changed') 'Domain-only change'
$html=ConvertTo-ObservationChangesHtml @((Compare-DhcpObservation $a $b))
Assert ($html.Contains('DNSDomain') -and -not $html.Contains('<changed>') -and $html.Contains('BeforePath')) 'Changed fields and provenance rendered with HTML encoding'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].DHCPLeaseObtained='2026-01-01T10:00:00Z'
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Changed') 'Lease became available, not a refresh from a known prior instant'
$b.Checks[1].Data[0].DHCPServer='192.0.2.9'
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Changed') 'Configuration overrides lease refresh'
$b=New-DhcpReviewFixture;[array]::Reverse($b.Checks[1].Data);[array]::Reverse($b.Checks[0].Data)
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Unchanged') 'Record order irrelevant'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].PSObject.Properties.Remove('DHCPServer')
$change=Compare-DhcpObservation $a $b
Assert ($change.Outcome -eq 'Not assessed' -and ($change.Reasons.Explanation -join ' ') -match 'Missing property DHCPServer') 'Missing property is not null or unchanged'
$b=New-DhcpReviewFixture;$b.Checks[1].Status='Failed'
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'Failed source'
$b=New-DhcpReviewFixture;$b.Checks[0].Data[0].InterfaceGuid=$b.Checks[0].Data[1].InterfaceGuid
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'Ambiguous identity'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].SettingID=$null;$b.Checks[0].Data[0].InterfaceGuid=$null
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'No alias/index matching fallback'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].DNSDomain=$null
$change=Compare-DhcpObservation $a $b
Assert ($change.ChangedFields[0].AfterValueState -eq 'ObservedNull') 'Explicit null preserved'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].DefaultIPGateway=@()
Assert ((Compare-DhcpObservation $a $b).ChangedFields[0].AfterValueState -eq 'ObservedEmpty') 'Explicit empty preserved'
$b=New-DhcpReviewFixture;$b.Checks[1].Data=@($b.Checks[1].Data|Select-Object -Skip 1)
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'Missing record not removal'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].SettingID='invalid'
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'Malformed identity not silently ignored'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].InterfaceIndex=99;$b.Checks[0].Data[0].InterfaceIndex=99
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Unchanged') 'Stable identity survives interface index change'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].PSObject.Properties.Remove('DHCPLeaseExpires')
Assert ((Compare-DhcpObservation $a $b).Outcome -eq 'Not assessed') 'Missing lease field is not unchanged'
Write-Host "PASS: $script:count DHCP observation assertions on $($PSVersionTable.PSVersion)."
