#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Connectivity','Orchestration','Observation')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1')
$work=New-TestWorkRoot;$script:files=@{};$script:analysisCount=0;$script:htmlCount=0;$count=0
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.7.0';IsElevated=$false;StartedAt='2026-01-01T00:00:00Z'}}
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text}
$script:realLogical=${function:Get-LogicalNetworkModel}
function Get-LogicalNetworkModel {param($Evidence);$script:analysisCount++;throw 'Injected analysis failure'}
$script:realHtml=${function:ConvertTo-DiagnosticHtml}
function ConvertTo-DiagnosticHtml {param($Evidence,$OutputDirectory);$script:htmlCount++;& $script:realHtml $Evidence $OutputDirectory}
$mock={param($definition,$timeout,$directory);[pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();Error=$null}}
$run=Invoke-SnapshotRun -RepositoryRoot $root -OutputRoot $work -CheckExecutor $mock
$saved=$script:files[$run.JsonPath]|ConvertFrom-Json
Assert ($saved.CollectionStatus -eq 'Complete' -and $saved.Checks.Count -gt 15) 'Raw checks continued through analysis failure'
Assert ($saved.Analysis.Status -eq 'Partial' -and $null -eq $saved.LogicalNetwork) 'Failed analysis cannot retain stale values'
Assert (@($saved.Analysis.Sections | Where-Object Status -eq 'Complete').Count -ge 3) 'Unrelated analysis completes'
Assert ($script:analysisCount -eq 1 -and $script:htmlCount -eq 1) 'Derived analysis and HTML run once at finalization'
Assert ($saved.Publication.HtmlEvidenceRevision -eq $saved.Revision) 'HTML revision attributed'
$html=$script:files[$run.HtmlPath]
Assert ($html.Contains('Competing DHCP servers: not assessed.') -and $html.Contains('Analysis unavailable')) 'First screen exposes limitations'
[IO.File]::WriteAllText((Join-Path $work 'synthetic-summary.html'),$html)
Write-Host "Synthetic HTML: $(Join-Path $work 'synthetic-summary.html')"
function ConvertTo-DiagnosticHtml {throw [InvalidOperationException]::new('Injected rendering failure')}
$caught=$null;try{Write-DiagnosticReport $run.Evidence $work}catch{$caught=$_}
$saved=$script:files[(Join-Path $work 'evidence.json')]|ConvertFrom-Json
Assert ($caught -and $caught.Exception.Data['ArtifactStage'] -eq 'Html') 'HTML-only failure is terminating and classified'
Assert ($saved.Checks.Count -gt 15 -and $saved.Publication.Html -eq 'Failed') 'Canonical raw evidence survives rendering failure'
foreach($scenario in @('Json','Html','Both')){
    $dir=Join-Path $work $scenario;$null=[IO.Directory]::CreateDirectory($dir)
    $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$output=& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'fixtures\FinalizationFault.ps1') -RepositoryRoot $root -Work $dir -Scenario $scenario -Model 2>&1;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
    $result=Get-Content -LiteralPath (Join-Path $dir 'fault-result.json') -Raw | ConvertFrom-Json
    Assert ($code -ne 0 -and $result.FaultReached) "Actual file process fails at injected final stage: $scenario"
    Assert ($result.RecoverableSamples -gt 0 -and $result.HasInner) "Earlier checkpoint and original exception retained: $scenario"
    if($scenario -eq 'Both'){Assert $result.HasCollectionError 'Both collection and finalization errors retained'}
}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='MODELED'}}
function Get-ObservationState {throw 'Injected sample comparison analysis failure'}
$script:time=0
$mock={param($definition,$timeout,$directory);$script:time+=0.01;[pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();Error=$null}}
$observation=Invoke-ObservationRun -RepositoryRoot $root -OutputRoot $work -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $mock -ElapsedClock {$script:time} -WaitAction {param($seconds);$script:time+=$seconds}
Assert ($observation.Evidence.Samples.Count -eq 2 -and $observation.Evidence.CollectionStatus -eq 'Complete') 'Analysis failure cannot stop subsequent sample collection'
$sample=$script:files[(Join-Path $observation.Directory 'sample-0001.json')]|ConvertFrom-Json
Assert ($sample.Checks.Count -ge 8 -and $sample.Analysis.Status -eq 'Partial' -and $sample.Changes.Count -eq 0) 'Sample raw checks survive failed comparison without stale values'
Assert (@($sample.Analysis.Sections | Where-Object Status -eq Complete).Count -eq 2) 'Other sample analysis sections survive comparison failure'
. (Join-Path $root 'src\Verification.ps1')
# Export the modeled bytes as test fixtures, with real hashes, to verify the
# actual orchestrator's artifact shape. This is not an atomic-write test.
foreach($path in @($script:files.Keys | Where-Object {$_.StartsWith($observation.Directory+'\')})){
    [IO.File]::WriteAllText($path,$script:files[$path])
}
foreach($reference in $observation.Evidence.Samples){$reference.Sha256=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath (Join-Path $observation.Directory $reference.Path) -Algorithm SHA256).Hash}
$observationPath=Join-Path $observation.Directory 'evidence.json'
[IO.File]::WriteAllText($observationPath,(ConvertTo-Json $observation.Evidence -Depth 32))
# Restore the real hash command for the verifier; collection above was modeled.
Remove-Item -LiteralPath Function:\Get-FileHash
$verification=Test-DiagnosticArtifact $observationPath
Assert ($verification.Status -eq 'Valid') ('Actual modeled observation artifacts verify: '+($verification.Issues -join '; '))
# Inspect a populated synthetic report too, including escaped text and scoped links.
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
${function:Get-LogicalNetworkModel}=$script:realLogical
${function:ConvertTo-DiagnosticHtml}=$script:realHtml
$fixture=New-DhcpReviewFixture -Current
$baseline=New-DhcpReviewFixture;$baselinePath=Join-Path $work 'synthetic-baseline.json'
[IO.File]::WriteAllText($baselinePath,(ConvertTo-Json $baseline -Depth 24))
$retained=Read-ContextInput $baselinePath Baseline SYNTHETIC
$fixture.Checks[0].Data[0].Status='Up';$fixture.Checks[3].Data[0].ConnectionState=1
$fixture.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($retained)},[pscustomobject]@{Name='Expectations';Status='Success';Data=@([pscustomobject]@{Version=1;Defaults=[pscustomobject]@{AllowedDhcpServers=@('192.0.2.9')};Interfaces=@()})})
$null=Write-DiagnosticReport $fixture (Join-Path $work 'raw-baseline') -RawOnly
$raw=$script:files[(Join-Path $work 'raw-baseline\evidence.json')] | ConvertFrom-Json
Assert ($raw.ContextInputs[0].Data[0].Path -eq '/ContextEvidence/Baseline' -and $raw.ContextEvidence.Baseline.Checks.Count -gt 0 -and $null -eq $raw.DhcpSummary) 'Raw baseline checkpoint has one resolving source store and no stale current analysis'
$paths=Write-DiagnosticReport $fixture (Join-Path $work 'populated')
$html=$script:files[$paths.HtmlPath]
Assert ($html.Contains('Synthetic &lt;1&gt;') -and -not $html.Contains('Synthetic <1>')) 'Synthetic interface aliases safely encoded'
Assert ($html.Contains('Run outcome') -and $html.Contains('Interface source coverage and evidence') -and $html.Contains('<details>')) 'Populated overview and expandable evidence are present'
Assert ($html.Contains('ForwardProgression') -and $html.Contains('Mismatch')) 'Precise lease progression and policy mismatch visible'
$ids=@([regex]::Matches($html,'id="([^"]+)"') | ForEach-Object {$_.Groups[1].Value})
$unresolved=@([regex]::Matches($html,'href="#([^"]+)"') | Where-Object {$_.Groups[1].Value -notin $ids})
Assert ($unresolved.Count -eq 0) 'All synthetic HTML scoped evidence links resolve'
Assert ($html -notmatch '<script|<iframe|src="https?://') 'Self-contained HTML has no active external content'
[IO.File]::WriteAllText((Join-Path $work 'populated-summary.html'),$html)
Write-Host "Populated synthetic HTML: $(Join-Path $work 'populated-summary.html')"
function Set-AtomicText {throw [IO.IOException]::new('Injected canonical write failure')}
$failure=$null;try{Write-CanonicalEvidence $fixture (Join-Path $work 'classification.json')}catch{$failure=$_}
Assert ($failure.Exception.Data['ArtifactStage'] -eq 'CanonicalPublication') 'Canonical I/O failure classified separately'
function ConvertTo-Json {throw [FormatException]::new('Injected serialization failure')}
$failure=$null;try{Write-CanonicalEvidence $fixture (Join-Path $work 'classification.json')}catch{$failure=$_}
Assert ($failure.Exception.Data['ArtifactStage'] -eq 'JsonSerialization') 'Serialization failure classified before I/O'
Write-Host "PASS: $count reliability model assertions; modeled persistence, real child script exit codes."
