#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Connectivity','Orchestration')){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\tests\additional-model-'+[guid]::NewGuid().ToString('N'))
$script:count=0;$script:definitions=@()
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.5.0';IsElevated=$false;StartedAt=[DateTimeOffset]::Now.ToString('o')}}
function Write-DiagnosticReport {param($Evidence,$Directory);[pscustomobject]@{JsonPath='mock';HtmlPath='mock'}}
$mock={param($definition,$timeout,$directory)
    $script:definitions+=$definition
    $data=@();if($definition.Arguments.Kind -eq 'Resolve'){$data=@([pscustomobject]@{Outcome='Success';Evidence=@([pscustomobject]@{IPAddress='192.0.2.80'})})}
    [pscustomobject]@{Name=$definition.Name;Status=$(if($definition.Name -eq 'IncidentContext'){'Failed'}else{'Success'});Data=$data;Error=$null}
}
$run=Invoke-SnapshotRun -RepositoryRoot $root -IncidentContextPath (Join-Path $work 'invalid.json') -CheckExecutor $mock -TestOutputRoot $work
Assert ($run.Evidence.CollectionStatus -eq 'Complete' -and $run.Evidence.SchemaVersion -eq 11) 'Incident failure isolated and schema versioned'
Assert (@($run.Evidence.Checks|Where-Object { $_.Name -eq 'IncidentContext' -and $_.Status -eq 'Failed' }).Count -eq 1) 'Incident failed check retained'
Assert (@($script:definitions|Where-Object FunctionName -eq 'Invoke-ConnectivityProbe').Count -eq 0) 'No probes by default'
Assert (@($script:definitions|Where-Object Name -like 'Proxy:*').Count -eq 3) 'User machine and WinHTTP inventory separate'
Assert (@($script:definitions|Where-Object Name -eq 'AdapterBindings').Count -eq 1) 'Bindings collected once'
$script:definitions=@()
$run=Invoke-SnapshotRun -RepositoryRoot $root -CheckExecutor $mock -TestOutputRoot $work -IncludeConnectivityTests -ProbeInterfaceIndex 7 -ProbeSourceAddress '192.0.2.10' -MaxInterfaceProbes 3
$probes=@($script:definitions|Where-Object FunctionName -eq 'Invoke-ConnectivityProbe')
Assert ($probes.Count -eq 3) 'Bounded interface test volume includes resolution'
Assert (@($probes|Where-Object {$_.Arguments.RequestedInterfaceIndex -ne 7 -or $_.Arguments.RequestedSourceAddress -ne '192.0.2.10'}).Count -eq 0) 'Explicit worker binding inputs'
Assert (@($run.Evidence.Checks|Where-Object Name -eq 'Connectivity:Budget').Count -eq 1) 'Exhausted budget explicit'
Write-Host "PASS: $script:count additional orchestration model assertions; mocked persistence and collectors, no probes."
