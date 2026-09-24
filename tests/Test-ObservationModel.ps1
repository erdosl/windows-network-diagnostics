#requires -Version 5.1
# Control-flow test only. Atomic persistence has its own real-I/O suite.
$ErrorActionPreference='Stop'
Import-Module Microsoft.PowerShell.Utility
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\tests\observation-model-'+[guid]::NewGuid().ToString('N'))
$script:files=@{};$script:calls=0;$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='SYNTHETIC-NOT-A-REAL-HASH'}}
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.5.0';IsElevated=$false;StartedAt=[DateTimeOffset]::Now.ToString('o')}}
$mock={param($definition,$timeout,$directory)
    $script:calls++
    if($timeout -gt 10 -or $timeout -lt 1){throw 'Worker budget not bounded'}
    [pscustomobject]@{Name=$definition.Name;Status=$(if($definition.Name -eq 'Routes'){'TimedOut'}else{'Success'});Data=@();Error=$null}
}
$cancel={ $script:calls -ge 8 }
$run=Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $mock -CancelRequested $cancel -TestOutputRoot $work
Assert ($run.Evidence.CollectionStatus -eq 'Interrupted') 'Explicit interrupted session'
Assert ($run.Evidence.Samples.Count -eq 1) 'One sample, no overlap/queued samples'
$sample=$script:files[(Join-Path $run.Directory 'sample-0000.json')]|ConvertFrom-Json
Assert (@($sample.Checks|Where-Object Status -eq 'TimedOut').Count -eq 1) 'Timeout evidence retained'
Assert (@($sample.Checks|Where-Object Name -like 'Events:*').Count -gt 0) 'Remaining checks continued'
Assert ($sample.StartedAt -and $sample.CompletedAt) 'Sample timestamps retained'
$script:calls=0
$throws={param($definition,$timeout,$directory);throw 'Synthetic interruption'}
$failed=$false;try{Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -CheckExecutor $throws -TestOutputRoot $work}catch{$failed=$true}
Assert $failed 'Unexpected interruption propagated'
$manifests=@($script:files.Keys|Where-Object {$_ -like '*evidence.json'}|ForEach-Object {$script:files[$_]|ConvertFrom-Json})
Assert (@($manifests|Where-Object CollectionStatus -eq 'Incomplete').Count -eq 1) 'Partial manifest never appears complete'
Write-Host "PASS: $script:count observation model assertions; mocked persistence and collectors, not an atomic-write validation."
