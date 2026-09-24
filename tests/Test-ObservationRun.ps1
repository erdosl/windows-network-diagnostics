#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\tests\observation-'+[guid]::NewGuid().ToString('N'))
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.5.0';IsElevated=$false;StartedAt=[DateTimeOffset]::Now.ToString('o')}}
$script:calls=0;$script:busy=$false
$mock={param($definition,$timeout,$directory)
    if($script:busy){throw 'Overlapping collection'};$script:busy=$true;$script:calls++
    try{[pscustomobject]@{Name=$definition.Name;Status=$(if($definition.Name -eq 'Routes'){'Failed'}else{'Success'});Data=@();Error=$null}}
    finally{$script:busy=$false}
}
$cancel={ $script:calls -ge 8 }
$run=Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $mock -CancelRequested $cancel -TestOutputRoot $work
if($run.Evidence.CollectionStatus -ne 'Interrupted'){throw 'Interruption not explicit'}
$saved=Get-Content -LiteralPath (Join-Path $run.Directory 'evidence.json') -Raw | ConvertFrom-Json
if($saved.Samples.Count -ne 1){throw 'Expected one immutable sample reference'}
$sample=Get-Content -LiteralPath (Join-Path $run.Directory $saved.Samples[0].Path) -Raw | ConvertFrom-Json
if(@($sample.Checks | Where-Object { $_.Name -eq 'Routes' -and $_.Status -eq 'Failed' }).Count -ne 1){throw 'Failed sample source lost'}
if(-not $sample.StartedAt -or -not $sample.CompletedAt){throw 'Missing sample timestamps'}
if($script:busy){throw 'Mock cleanup not complete'}
Write-Host 'PASS: 5 observation orchestration assertions; mocked collectors, real atomic writes.'
