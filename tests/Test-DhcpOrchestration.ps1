#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core.ps1','State.ps1','Execution.ps1','Events.ps1','Collection.ps1','Connectivity.ps1','Orchestration.ps1')){. (Join-Path $root "src\$file")}
$script:count=0
function Assert-Run {param($Condition,$Message);if(-not $Condition){throw $Message};$script:count++}
function New-SnapshotIdentity { [pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.4.0';IsElevated=$false;StartedAt='2026-01-01T10:00:00+00:00'} }
$workspace=Join-Path $root ('output\tests\dhcp-orchestration-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $workspace
$badPath=Join-Path $workspace 'bad input.json'
'{' | Set-Content $badPath
$script:checkpointCount=0
$observer={param($e,$directory)
    $script:checkpointCount++
    if($script:checkpointCount -eq 1){Assert-Run ($e.CollectionStatus -eq 'Incomplete' -and $e.Checks.Count -eq 0 -and $e.DhcpSummary.CompetingDhcpServers -eq 'Not assessed') 'Initial incomplete checkpoint precedes optional reads'}
}
$mock={param($definition,$timeout,$directory)
    if($definition.FunctionName -eq 'Invoke-ConnectivityProbe'){throw 'Unexpected active probe'}
    [pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();StartedAt='2026-01-01T10:00:00+00:00';CompletedAt='2026-01-01T10:00:01+00:00'}
}
$run=Invoke-SnapshotRun -RepositoryRoot $root -PreviousSnapshotPath $badPath -ExpectationsPath $badPath -CheckExecutor $mock -CheckpointObserver $observer -TestOutputRoot $workspace
Assert-Run ($run.Evidence.CollectionStatus -eq 'Complete' -and $run.Evidence.SchemaVersion -eq 7) 'Malformed optional files do not discard completed snapshot'
Assert-Run ($run.Evidence.SnapshotComparison.Status -eq 'Failed' -and $run.Evidence.ExpectationAssessment.Status -eq 'Failed') 'Both optional failures explicit'
Assert-Run (@($run.Evidence.Checks | Where-Object Name -eq 'Windows').Count -eq 1) 'Normal checks continued'
Assert-Run (($run.Evidence.Checks | Where-Object Name -eq 'Connectivity').Status -eq 'Skipped') 'Active probes remain disabled'
Assert-Run ($script:checkpointCount -gt 10) 'Incremental checkpoints still produced'
$saved=Read-DiagnosticEvidence $run.JsonPath
Assert-Run ($saved.ContextInputs.Count -eq 2 -and $saved.CollectionStatus -eq 'Complete') 'Optional input status saved atomically'
Assert-Run (@(Get-ChildItem $run.JsonPath.Substring(0,$run.JsonPath.LastIndexOf('\')) -Directory -Filter '.worker-*').Count -eq 0) 'Optional input workers cleaned up'
Write-Host "PASS: $script:count DHCP orchestration assertions on $($PSVersionTable.PSVersion)."
