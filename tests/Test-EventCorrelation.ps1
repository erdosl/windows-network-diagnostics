#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\State.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$script:count=0
function Assert-Event {param($Condition,$Message);if(-not $Condition){throw $Message};$script:count++}
function New-EventFixture {
    $e=New-DhcpReviewFixture -Current
    foreach($a in $e.Checks[0].Data){$a | Add-Member NoteProperty InterfaceType 6}
    $e.Checks[-1].Data[0].Events=@(1001,1003 | ForEach-Object {[pscustomobject]@{Id=$_;ProviderName='Synthetic-DHCP';TimeCreated='2026-01-01T08:00:00+00:00';Message='Historical <cloned identity> error.';Xml='<Event><EventData><Data Name="HWAddress">0x02AABBCCDDEE</Data></EventData></Event>'}})
    $e
}
function Context {param($e,$baseline);@(Get-HistoricalEventContext $e @(Get-DhcpInterfaceContext $e) $baseline)}
function Add-NoMac {param($e,$Type,$Physical)
    $e.Checks[0].Data += [pscustomobject]@{InterfaceIndex=99;InterfaceGuid='99999999-9999-9999-9999-999999999999';Name='Synthetic <other>';MacAddress=$null;InterfaceType=$Type;HardwareInterface=$Physical;Status='Up'}
}
$e=New-EventFixture
$c=(Context $e)[0].Correlations[0]
Assert-Event ($c.Confidence -eq 'No current identifier match' -and $c.NoCurrentMacMatch -eq $true -and $c.ReasonCode -eq 'NoCurrentIdentifierMatch') 'Sufficient inventory establishes unmatched MAC'
foreach($type in @(24,131,23)){
    $e=New-EventFixture;Add-NoMac $e $type $false
    Assert-Event ((Context $e)[0].Correlations[0].NoCurrentMacMatch -eq $true) "Explicit non-MAC type $type does not veto absence"
}
$e=New-EventFixture
$e.Checks[2].Data += [pscustomobject]@{InterfaceIndex=100;IPAddress='198.51.100.40';AddressFamily=2;PrefixLength=24}
Assert-Event ((Context $e)[0].Correlations[0].NoCurrentMacMatch -eq $true) 'IP-only record is not an unidentified inventoried adapter'
foreach($status in @('Failed','Unavailable','TimedOut')){
    $e=New-EventFixture;$e.Checks[0].Status=$status
    $c=(Context $e)[0].Correlations[0]
    Assert-Event ($c.Confidence -eq 'Not assessed' -and $null -eq $c.NoCurrentMacMatch -and $c.ReasonCode -eq 'AdapterInventoryNotSuccessful' -and $c.Reason -match $status) "Inventory $status explicitly unassessed"
}
$e=New-EventFixture;$e.Checks=@($e.Checks | Where-Object Name -ne 'Adapters')
Assert-Event ((Context $e)[0].Correlations[0].ReasonCode -eq 'AdapterInventoryMissing') 'Missing inventory distinct reason'
foreach($spec in @(@(6,$true),@(6,$false),@(999,$false),@(24,$true))){
    $e=New-EventFixture;Add-NoMac $e $spec[0] $spec[1]
    $c=(Context $e)[0].Correlations[0]
    Assert-Event ($c.Confidence -eq 'Not assessed' -and $c.ReasonCode -eq 'RelevantIdentityEvidenceMissing' -and $null -eq $c.NoCurrentMacMatch) 'Missing relevant/unknown/contradictory MAC remains unassessed'
}
$e=New-EventFixture;$e.Checks[0].Data[0].MacAddress='malformed'
Assert-Event ((Context $e)[0].Correlations[0].ReasonCode -eq 'RelevantIdentityEvidenceMissing') 'Invalid adapter MAC insufficient'
$e=New-EventFixture;$e.Checks[0].Data[0].MacAddress='02-AA-BB-CC-DD-EE';Add-NoMac $e 6 $true
$c=(Context $e)[0].Correlations[0]
Assert-Event ($c.Confidence -eq 'Current exact identifier match' -and $c.NoCurrentMacMatch -eq $false -and $c.CurrentMatches.Count -eq 1) 'Positive exact match survives other missing identities'
$e.Checks[0].Data[1].MacAddress='02-AA-BB-CC-DD-EE'
$c=(Context $e)[0].Correlations[0]
Assert-Event ($c.Confidence -eq 'Ambiguous match' -and $c.CurrentMatches.Count -eq 2 -and $c.NoCurrentMacMatch -eq $false) 'Multiple exact current matches ambiguous'
$old=New-EventFixture;$old.RunId='synthetic-before-recovery';$old.Checks[0].Data[0].MacAddress='02-AA-BB-CC-DD-EE'
$baseline=[pscustomobject]@{Identity=[pscustomobject]@{RunId=$old.RunId};Interfaces=@(Get-DhcpInterfaceContext $old)}
$e=New-EventFixture;$c=(Context $e $baseline)[0].Correlations[0]
Assert-Event ($c.Confidence -eq 'Historical-only match' -and $c.NoCurrentMacMatch -eq $true -and $c.HistoricalMatches[0].RunId -eq $old.RunId) 'Historical-only association scoped to baseline'
$e.Checks[0].Status='Unavailable';$c=(Context $e $baseline)[0].Correlations[0]
Assert-Event ($c.Confidence -eq 'Not assessed' -and $null -eq $c.NoCurrentMacMatch -and $c.HistoricalMatches.Count -eq 1) 'Historical association preserved without asserting current absence'
$e=New-EventFixture;$e.Checks[-1].Data[0].Events[0].Xml='<Event/>'
$event=(Context $e)[0]
Assert-Event ($event.CorrelationSummary -like 'Not assessed*' -and $event.AssessmentReasons[0].ReasonCode -eq 'NoRecognizedStructuredIdentifier') 'No XML identifier never falls back to message'
$dir=Join-Path $root ('output\tests\event-correlation-'+[guid]::NewGuid().ToString('N'))
$e=New-EventFixture;Add-NoMac $e 131 $false
# Equivalent to the reported recovered baseline: it does not contain the old MAC.
$recovered=[pscustomobject]@{Identity=[pscustomobject]@{RunId='synthetic-after-recovery'};Interfaces=@(Get-DhcpInterfaceContext $e)}
$events=Context $e $recovered
foreach($event in $events){
    $c=$event.Correlations[0]
    Assert-Event ($event.CorrelationSummary -eq $c.Confidence -and $c.Confidence -eq 'No current identifier match' -and $c.CurrentInventoryStatus -eq 'Success' -and $c.NoCurrentMacMatch -eq $true -and $c.HistoricalMatches.Count -eq 0) "Regression event $($event.EventId) consistent unmatched result"
}
$raw=ConvertTo-Json $e.Checks -Depth 24 -Compress
$paths=Write-DiagnosticReport $e $dir
$html=Get-Content -Raw $paths.HtmlPath
Assert-Event ($html.Contains('No current identifier match') -and $html.Contains('Historical &lt;cloned identity&gt;')) 'HTML exposes escaped event and corrected result'
Assert-Event ((ConvertTo-Json $e.Checks -Depth 24 -Compress) -ceq $raw -and $e.ContextEvidence.ContractVersion -eq 2) 'Raw evidence and contract version preserved'
$e=New-EventFixture;Add-NoMac $e 6 $false;Update-DhcpContext $e
$html=ConvertTo-DhcpContextHtml $e
$event=(Context $e)[0]
Assert-Event ($event.CorrelationSummary -eq 'Not assessed' -and $html.IndexOf('RelevantIdentityEvidenceMissing:') -lt $html.IndexOf('<summary>Identifiers, provenance and raw evidence')) 'HTML explains unassessed result before raw details'
Assert-Event ($html.Contains($event.Correlations[0].Reason)) 'HTML reason agrees with structured reason'
$e=New-EventFixture;$e.Checks[0].Data=@()
Assert-Event ((Context $e)[0].Correlations[0].ReasonCode -eq 'EmptyAdapterInventory') 'Empty success is not proof of complete identity coverage'
$e=New-EventFixture;$e.Checks[0].Data[0].MacAddress='02-AA-BB-CC-DD-EE'
$baseline.Interfaces+= $baseline.Interfaces[0]
Assert-Event ((Context $e $baseline)[0].Correlations[0].Confidence -eq 'Current exact identifier match') 'Unique current match remains explicit despite baseline ambiguity'
Write-Host "PASS: $script:count event correlation assertions on $($PSVersionTable.PSVersion)."
