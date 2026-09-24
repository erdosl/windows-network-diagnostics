#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\State.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$script:count=0
function Assert-Review {param($Condition,$Message);if(-not $Condition){throw "Assertion failed: $Message"};$script:count++}
function Clone-Review {param($Value);ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 24)}
function Resolve-ReviewReference {
    param($Evidence,[string]$Path)
    $node=$Evidence
    foreach($part in $Path.TrimStart('/').Split('/')){
        if($node -is [array]){$node=$node[[int]$part]}else{$node=$node.PSObject.Properties[$part].Value}
    }
    $node
}
$workspace=Join-Path $root ('output\tests\dhcp-review-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $workspace
$baseline=New-DhcpReviewFixture
$baseline.SchemaVersion=6
$baseline | Add-Member NoteProperty SnapshotComparison ([pscustomobject]@{RecursiveHistory='DO_NOT_IMPORT_PRIOR_HISTORY'})
$baseline | Add-Member NoteProperty ContextEvidence ([pscustomobject]@{Baseline=[pscustomobject]@{Checks=@('DO_NOT_IMPORT_PRIOR_HISTORY')}})
$baselinePath=Join-Path $workspace 'baseline.json'
$baseline | ConvertTo-Json -Depth 24 | Set-Content $baselinePath -Encoding UTF8
$retained=Read-ContextInput $baselinePath Baseline SYNTHETIC
$current=New-DhcpReviewFixture -Current
$current.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($retained)})
$rawBefore=ConvertTo-Json $current.Checks -Depth 24 -Compress
$paths=Write-DiagnosticReport $current (Join-Path $workspace 'report')
$json=Get-Content -Raw $paths.JsonPath
$saved=ConvertFrom-Json $json
$html=Get-Content -Raw $paths.HtmlPath
Assert-Review ($json -match '"LeaseObtained":\s*null') 'Missing dates serialize as JSON null'
Assert-Review ($null -eq $saved.DhcpSummary.Interfaces[0].Values.LeaseExpires) 'Missing date survives JSON round trip as null'
Assert-Review ($saved.DhcpSummary.Interfaces[1].Values.LeaseExpires -is [string] -and $saved.DhcpSummary.Interfaces[1].Values.LeaseExpires -match '\+00:00$') 'Valid dates offset strings'
Assert-Review ((ConvertTo-Json $current.Checks -Depth 24 -Compress) -ceq $rawBefore) 'Raw current evidence unchanged'
Assert-Review (-not $json.Contains('DO_NOT_IMPORT_PRIOR_HISTORY')) 'Baseline does not import comparisons or nested context history'
Assert-Review ($saved.ContextEvidence.Baseline.Checks.Count -eq 4) 'Only consumed check families retained'
Assert-Review (-not $saved.ContextInputs[0].Data[0].Identity -and $saved.ContextInputs[0].Data[0].Path -eq '/ContextEvidence/Baseline') 'Input points to canonical baseline store'
$gateway=@($saved.SnapshotComparison.Changes | Where-Object { $_.Field -eq 'Gateways' -and $_.Outcome -eq 'Changed' })[0]
$before=Resolve-ReviewReference $saved $gateway.BeforeReference.Path
$after=Resolve-ReviewReference $saved $gateway.AfterReference.Path
Assert-Review ($gateway.BeforeReference.Scope -eq 'Baseline' -and $gateway.BeforeReference.RunId -eq 'baseline' -and $before.Values.Gateways[0] -eq '192.0.2.1') 'Baseline reference scope, run and value correct'
Assert-Review ($gateway.AfterReference.Scope -eq 'Current' -and $gateway.AfterReference.RunId -eq 'current' -and $after.Values.Gateways[0] -eq '192.0.2.2') 'Current reference scope, run and value correct'
Assert-Review ((Resolve-ReviewReference $saved $before.Sources.DHCPAndGateways.EvidenceReferences[0]).DefaultIPGateway[0] -eq '192.0.2.1') 'Baseline raw record resolves inside retained store'
Assert-Review ((Resolve-ReviewReference $saved $after.Sources.DHCPAndGateways.EvidenceReferences[0]).DefaultIPGateway[0] -eq '192.0.2.2') 'Current raw record resolves inside current Checks'
Assert-Review ($null -eq $before.Sources.DHCPAndGateways.Records -and $null -eq $gateway.BeforeSources) 'No full source records in summaries/comparison rows'
$sameAdapter=@($saved.SnapshotComparison.Changes | Where-Object Identity -eq $gateway.Identity)
Assert-Review (@($sameAdapter | ForEach-Object {$_.BeforeReference.Path} | Select-Object -Unique).Count -eq 1) 'Multiple comparison rows reuse one baseline interface reference'
Assert-Review ($saved.HistoricalEventContext[0].Correlations[0].HistoricalMatches[0].Path -eq $gateway.BeforeReference.Path) 'Events reuse same baseline evidence'
Assert-Review ((Resolve-ReviewReference $saved $saved.HistoricalEventContext[0].RawReference.Path).Id -eq 1001) 'Raw event reference resolves'
Assert-Review ($gateway.StateNote -ceq 'Retained configuration changed on a disconnected adapter.') 'Both-disconnected context explicit'
Assert-Review ($gateway.BeforeContext.Alias -eq 'Synthetic <1>' -and $gateway.AfterContext.InterfaceIndex -eq 1) 'Readable aliases/indices retained with GUID'
Assert-Review ($html.IndexOf('Retained configuration changed on a disconnected adapter.') -lt $html.IndexOf('<summary>Unchanged (')) 'Changed entries before collapsed unchanged'
Assert-Review ($html.IndexOf('Lease refreshed</td>') -lt $html.IndexOf('<summary>Not assessed (')) 'Lease refresh before collapsed not assessed'
Assert-Review ($html.Contains('Changed: 1; lease refreshed: 2;') -and $html.Contains('baseline;') -and $html.Contains('current;')) 'Counts and run identity shown'
Assert-Review ($html.Contains('Synthetic &lt;1&gt;') -and $html.Contains($gateway.Identity)) 'Escaped adapter alias and stable identity details'
Assert-Review ($html.Contains('event 1001 | Synthetic-DHCP') -and $html.Contains('Historical &lt;DHCP&gt; message &amp; context.')) 'Readable event ID/provider and escaped description'
Assert-Review ($html.Contains('1 hours before snapshot start') -and $html.Contains('Current exact identifier match')) 'Readable age and correlation'
Assert-Review (-not $html.Contains('Historical <DHCP>')) 'Description never injected as markup'
# Recompute a loaded current report: canonical baseline retained once, no history expansion.
$firstLength=(ConvertTo-Json $saved -Depth 24 -Compress).Length
Update-DhcpContext $saved
Assert-Review ((ConvertTo-Json $saved -Depth 24 -Compress).Length -eq $firstLength) 'Repeated derivation does not grow baseline history'
$empty=New-DhcpReviewFixture
$empty.Checks[1].Data[0].DefaultIPGateway=@($null)
$empty.Checks[1].Data[0].DNSServerSearchOrder=@($null)
$emptyValues=(Clone-Review @(Get-DhcpInterfaceContext $empty))[0].Values
Assert-Review ($emptyValues.Gateways.Count -eq 0 -and $emptyValues.DnsServers.Count -eq 0) 'Empty derived address collections are [] rather than [null]'
$emptyJson=ConvertTo-Json $emptyValues -Compress
Assert-Review ($emptyJson -match '"Gateways":\[\]' -and $emptyJson -match '"DnsServers":\[\]') 'Actual serialization retains empty arrays'
$empty.Checks[1].Data[0].DHCPLeaseObtained='invalid'
Assert-Review ((Get-DhcpInterfaceContext $empty)[0].Availability.LeaseObtained -eq 'Invalid') 'Invalid date availability distinguished'
$empty.Checks[1].Data[0].DHCPEnabled=$false
Assert-Review ((Get-DhcpInterfaceContext $empty)[0].Availability.LeaseObtained -eq 'Not applicable') 'Disabled lease date not applicable'
$same=New-DhcpReviewFixture
$comparison=Compare-DhcpContext @(Get-DhcpInterfaceContext $same) $retained $same
Assert-Review ($comparison.Counts.Changed -eq 0 -and $comparison.Counts.LeaseRefreshed -eq 0) 'Schema 6/current normalization produces no false changes'
$same.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($retained)})
Update-DhcpContext $same
Assert-Review ((ConvertTo-DhcpContextHtml $same).Contains('No assessed configuration changes.')) 'No assessed changes message retains coverage'
$transition=New-DhcpReviewFixture -Current
$transition.Checks[0].Data[0].Status='Up';$transition.Checks[3].Data[0].ConnectionState=1
$transition.Checks[0].Data[0].Name='Renamed <adapter>'
$row=(Compare-DhcpContext @(Get-DhcpInterfaceContext $transition) $retained $transition).Changes | Where-Object {$_.Field -eq 'Gateways' -and $_.Outcome -eq 'Changed'}
Assert-Review ($row.StateNote -match 'Disconnected -> Connected' -and $row.BeforeContext.Alias -ne $row.AfterContext.Alias) 'State transition and both aliases visible'
$transition.Checks[0].Data[0].Status=$null;$transition.Checks[3].Data[0].ConnectionState=$null
$row=(Compare-DhcpContext @(Get-DhcpInterfaceContext $transition) $retained $transition).Changes | Where-Object {$_.Field -eq 'Gateways' -and $_.Outcome -eq 'Changed'}
Assert-Review ($row.StateNote -match 'unknown') 'Missing state explicitly unknown'
$future=New-DhcpReviewFixture -Current
$future.Checks[-1].Data[0].Events[0].TimeCreated='2026-01-01T10:00:00+00:00'
$future.Checks[-1].Data[0].Events[1].TimeCreated=$null;$future.Checks[-1].Data[0].Events[1].Message=$null
$context=@(Get-HistoricalEventContext $future @(Get-DhcpInterfaceContext $future) $retained)
Assert-Review ($context[0].AgeSeconds -eq -3600 -and (Format-ContextAge $context[0].AgeSeconds) -match 'future-dated') 'Future-dated event explicit without stale threshold'
Assert-Review ($null -eq $context[1].EventTime -and $null -eq $context[1].AgeSeconds -and $context[1].Description -eq 'Description unavailable') 'Missing event time/message explicit nulls'
$ambiguous=New-DhcpReviewFixture -Current
$ambiguous.Checks[0].Data[1].InterfaceGuid=$ambiguous.Checks[0].Data[0].InterfaceGuid
$ambiguous.Checks[1].Data[1].SettingID=$ambiguous.Checks[0].Data[0].InterfaceGuid
Assert-Review ((Get-HistoricalEventContext $ambiguous @(Get-DhcpInterfaceContext $ambiguous) $retained)[0].CorrelationSummary -eq 'Ambiguous match') 'Multiple explicit matches remain ambiguous'
$future.Checks[0].Status='Unavailable'
$future.Checks[-1].Data[0].Events[0].Xml='<Event><EventData><Data Name="HWAddress">020000000001</Data></EventData></Event>'
$context=@(Get-HistoricalEventContext $future @(Get-DhcpInterfaceContext $future) $retained)[0]
Assert-Review ($null -eq $context.Correlations[0].NoCurrentMacMatch -and $context.CorrelationSummary -like 'Not assessed*') 'Unavailable inventory not confirmed absence'
Assert-Review ($context.Correlations[0].HistoricalMatches[0].Scope -eq 'Baseline') 'Historical match still scoped when current inventory unavailable'
$transition.Checks[0].Data[0].Status='Disabled';$transition.Checks[3].Data[0].ConnectionState=0
$row=(Compare-DhcpContext @(Get-DhcpInterfaceContext $transition) $retained $transition).Changes | Where-Object {$_.Field -eq 'Gateways' -and $_.Outcome -eq 'Changed'}
Assert-Review ($row.StateNote -match 'Link/connection transition' -and $row.StateNote -notmatch '^Retained configuration changed') 'Different disconnected link states show transition'
Assert-Review ((Format-ContextTimestamp '2026-01-01T09:00:00.0000000+01:00') -eq '2026-01-01 09:00:00 +01:00') 'Readable timestamps keep explicit offsets'
$equivalent=New-DhcpReviewFixture
$equivalent.Checks[1].Data[1].DHCPLeaseObtained='2026-01-01T09:00:00+01:00'
$equivalent.Checks[1].Data[1].DHCPLeaseExpires='2026-01-01T11:00:00+01:00'
$comparison=Compare-DhcpContext @(Get-DhcpInterfaceContext $equivalent) $retained $equivalent
Assert-Review ($comparison.Counts.Changed -eq 0 -and $comparison.Counts.LeaseRefreshed -eq 0) 'Equivalent instants with different offsets are not configuration changes'
Write-Host "PASS: $script:count DHCP review assertions on $($PSVersionTable.PSVersion)."
