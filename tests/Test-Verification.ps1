#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Connectivity','Orchestration','Observation','Verification')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
function Assert($v,$m){if(-not $v){throw $m}}
# Real producers, synthetic collectors and ordinary fixture writes; not an atomic I/O test.
function Set-AtomicText {param($Path,$Text);[IO.File]::WriteAllText($Path,$Text)}
$execute={param($definition,$timeout,$directory);[pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();Error=$null}}
$run=Invoke-SnapshotRun -RepositoryRoot $root -OutputRoot $work -CheckExecutor $execute
$path=$run.JsonPath;$original=[IO.File]::ReadAllText($path)
$result=Test-DiagnosticArtifact $path
Assert ($result.Status -eq 'Valid') ($result.Issues -join '; ')
$mutations=@(
    {param($e);$e.CompletedAt=$null},
    {param($e);$e.Revision='1'},
    {param($e);$e.SchemaVersion='11'},
    {param($e);$e.Analysis.Status='Healthy'},
    {param($e);$e.Metadata.RunId=[guid]::NewGuid().ToString()},
    {param($e);$e.ConfigurationOrigins=@([pscustomobject]@{Reference='/Checks/999'})},
    {param($e);$e.VpnInterfaceContext=@([pscustomobject]@{RouteReferences=@('/Checks/999')})},
    {param($e);$e.DhcpSummary.Interfaces=@([pscustomobject]@{Sources=@{Adapters=@{Scope='Current';RunId=$e.RunId;EvidenceReferences=@('/Checks/999');CheckReferences=@('/Checks/0')}}})},
    {param($e);$e.DhcpSummary.Interfaces=@([pscustomobject]@{Sources=@{Adapters=@{Scope='Current';RunId='wrong';CheckReferences=@('/Checks/0')}}})}
)
foreach($mutate in $mutations){$e=$original|ConvertFrom-Json;& $mutate $e;Set-AtomicText $path (ConvertTo-Json $e -Depth 32);$r=Test-DiagnosticArtifact $path;Assert ($r.Status -eq 'Invalid') 'Invalid mutation accepted'}
$e=$original|ConvertFrom-Json
$e.Checks[0].Data=@([pscustomobject]@{Reference='/untrusted/provider/value';Path='/not/a/reference';Scope='raw'});
Set-AtomicText $path (ConvertTo-Json $e -Depth 32)
Assert ((Test-DiagnosticArtifact $path).Status -eq 'Valid') 'Raw provider strings misinterpreted as references'
$hash=(Get-FileHash -LiteralPath $path).Hash
$null=& powershell.exe -NoProfile -File (Join-Path $root 'Verify-NetworkDiagnostics.ps1') -Path $path
Assert ($LASTEXITCODE -eq 0 -and (Get-FileHash -LiteralPath $path).Hash -eq $hash) 'Bounded verifier exit/read-only behavior'
$script:time=0
$obs=Invoke-ObservationRun -RepositoryRoot $root -OutputRoot $work -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $execute -ElapsedClock {$script:time} -WaitAction {param($seconds);$script:time+=$seconds}
$path=Join-Path $obs.Directory 'evidence.json';$original=[IO.File]::ReadAllText($path)
$r=Test-DiagnosticArtifact $path;Assert ($r.Status -eq 'Valid') ($r.Issues -join '; ')
foreach($mutate in @(
    {param($e);$e.Samples[0].Sha256='bad'},
    {param($e);$e.Samples[1].Changes[0].BeforeEvidence.RunId='wrong'},
    {param($e);$e.Samples[1].Changes[0].BeforeEvidence.SourceCheck='missing'},
    {param($e);$e.Samples[1].Changes[0].BeforeEvidence.Scope='Unknown'},
    {param($e);$e.Samples[1].Changes[0] | Add-Member NoteProperty ChangedFields @([pscustomobject]@{BeforeArtifact='missing.json';BeforePath='/Checks/0';AfterArtifact='sample-0001.json';AfterPath='/Checks/0'}) -Force},
    {param($e);$e.CompletedAt='bad'}
)){$e=$original|ConvertFrom-Json;& $mutate $e;Set-AtomicText $path (ConvertTo-Json $e -Depth 32);Assert ((Test-DiagnosticArtifact $path).Status -eq 'Invalid') 'Invalid observation accepted'}
$e=$original|ConvertFrom-Json;$e.Samples[0].Path='..\outside.json';Set-AtomicText $path (ConvertTo-Json $e -Depth 32)
$rejected=$false;try{$null=Test-DiagnosticArtifact $path}catch{$rejected=$true};Assert $rejected 'Unsafe sample path accepted'
$e=$original|ConvertFrom-Json;$e.Samples=@();Set-AtomicText $path (ConvertTo-Json $e -Depth 32)
Assert ((Test-DiagnosticArtifact $path).Status -eq 'Valid') 'Zero-sample deadline outcome rejected'
$e.SchemaVersion=9;Set-AtomicText $path (ConvertTo-Json $e -Depth 32)
Assert ((Test-DiagnosticArtifact $path).Status -eq 'Unsupported') 'Older schema accepted'
Write-Host 'PASS: producer-shaped offline artifacts, structural/reference/hash separation, invalid mutations, raw-data isolation and bounded read-only command.'
