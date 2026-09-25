#requires -Version 5.1
# Control-flow/serialization regression, not validation of atomic replacement.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Connectivity','Orchestration')){. (Join-Path $root "src\$file.ps1")}
$script:count=0;$script:executed=@();$script:checkpoints=@()
function Assert-Condition {param([bool]$Condition,[string]$Message);if(-not $Condition){throw "Assertion failed: $Message"};$script:count++}
. (Join-Path $PSScriptRoot 'fixtures\Milestone2Orchestration.ps1')
function Write-DiagnosticReport {
    param($Evidence,$Directory)
    $script:serialized=ConvertTo-Json -InputObject $Evidence -Depth 24
    $script:checkpoints+=@($script:serialized | ConvertFrom-Json)
    [pscustomobject]@{JsonPath=(Join-Path $Directory 'evidence.json');HtmlPath=(Join-Path $Directory 'summary.html')}
}
$work=Join-Path $root ('output\tests\milestone2-model-'+[guid]::NewGuid().ToString('N'))
$run=Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $work -CheckExecutor $mock
$saved=$script:serialized | ConvertFrom-Json
Assert-Milestone2Continuation $run.Evidence $script:executed $saved
Assert-Condition (@($script:checkpoints | Where-Object {$_.CollectionStatus -eq 'Incomplete' -and $_.Checks.Count -eq 1 -and $_.Checks[0].Status -eq 'TimedOut'}).Count -gt 0) 'Serialized incomplete checkpoint retains timeout before continuation'
# Negative controls: the stronger oracle must fail actual loss, not just tolerate
# a new total. Each expected family, duplicate, order and timeout detail is tested.
for($i=0;$i -lt $saved.Checks.Count;$i++){
    $broken=$script:serialized | ConvertFrom-Json
    $broken.Checks=@(for($j=0;$j -lt $saved.Checks.Count;$j++){if($j -ne $i){$saved.Checks[$j]}})
    $rejected=$false;try{Assert-Milestone2Continuation $broken $script:executed $broken}catch{$rejected=$true}
    Assert-Condition $rejected "Missing result $i rejected"
}
foreach($mutation in @('Duplicate','Reordered','TimeoutLost','ErrorLost','Incomplete','CompletionLost','WrongRun','ExecutionMissing','PlanMissing')){
    $broken=$script:serialized | ConvertFrom-Json;$executed=$script:executed
    switch($mutation){
        'Duplicate' {$broken.Checks+=$broken.Checks[-1]}
        'Reordered' {$a=$broken.Checks[1];$broken.Checks[1]=$broken.Checks[2];$broken.Checks[2]=$a}
        'TimeoutLost' {$broken.Checks[0].Status='Success'}
        'ErrorLost' {$broken.Checks[0].Error=$null}
        'Incomplete' {$broken.CollectionStatus='Incomplete'}
        'CompletionLost' {$broken.CompletedAt=$null}
        'WrongRun' {$broken.RunId='different-run'}
        'ExecutionMissing' {$executed=@($executed | Where-Object Name -ne 'TimeZone')}
        'PlanMissing' {$broken.PlannedChecks=@($broken.PlannedChecks | Where-Object {$_ -ne 'TimeZone'})}
    }
    $rejected=$false;try{Assert-Milestone2Continuation $run.Evidence $executed $broken}catch{$rejected=$true}
    Assert-Condition $rejected "$mutation rejected"
}
Write-Host 'PASS: named passive-check sequence and serialized timeout/completion verified; missing, duplicate and reordered records rejected. Modeled persistence, no probes.'
