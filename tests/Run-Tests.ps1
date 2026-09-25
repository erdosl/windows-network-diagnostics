#requires -Version 5.1

<#
.SYNOPSIS
Run cataloged suites in separate bounded Windows PowerShell 5.1 processes.
.DESCRIPTION
Default catalog excludes loopback socket suites and live provider inspectors.
No capture or live probes run implicitly. Results never infer assertion totals.
.EXAMPLE
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
.EXAMPLE
.\tests\Run-Tests.ps1 -Suite Test-ReliabilityModel,Test-LeaseReliability
#>
[CmdletBinding()]
param([string[]]$Suite,[switch]$IncludeLoopbackTests,[switch]$IncludeLiveProviderChecks,[ValidateRange(10,600)][int]$SuiteTimeoutSeconds=180)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Run this runner with powershell.exe (Windows PowerShell 5.1).'}
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Execution')){. (Join-Path $root "src\$file.ps1")}
$models=@('Test-AdditionalOrchestrationModel','Test-ObservationModel','Test-LiveObservation','Test-CaptureEvidence','Test-Milestone2Continuation','Test-Windows11Evidence','Test-ReliabilityModel')
$workers=@('Test-Windows11Worker','Test-InventoryBoundaries','Test-EntryLoading','Test-OutputPlacement','Test-Verification')
$persistence=@('Test-Snapshot','Test-AdapterApipa','Test-DhcpContext','Test-DhcpReview','Test-SnapshotComparison','Test-EventCorrelation','Test-LogicalNetwork','Test-Dns','Test-Milestone2','Test-DhcpOrchestration','Test-ObservationRun','Test-CaptureImport','Test-PathPortability','Test-LongCheckout','Test-ReliabilityPersistence')
$synthetic=@('Test-AdditionalEvidence','Test-CaptureVlan','Test-InterfaceProbes','Test-Observation','Test-ObservationDhcp','Test-ObservationSerialization','Test-Presentation','Test-LeaseReliability','Test-ErrorClassification','Test-SourceSyntax')
$catalog=@{}
foreach($pair in @(@('Model',$models),@('Worker',$workers),@('Persistence',$persistence),@('Synthetic',$synthetic),@('Loopback',@('Test-Probes','Test-ProbeReview')),@('LiveProvider',@('Inspect-Windows11Providers')))){
    foreach($name in $pair[1]){$catalog[$name]=$pair[0]}
}
if($Suite){$Suite=@($Suite | ForEach-Object {$_ -split ','})}
else{$Suite=@($catalog.Keys | Where-Object {$catalog[$_] -notin @('Loopback','LiveProvider')} | Sort-Object)}
foreach($name in $Suite){
    if(-not $catalog.ContainsKey($name)){throw "Uncataloged suite: $name"}
    if($catalog[$name] -eq 'Loopback' -and -not $IncludeLoopbackTests){throw 'Loopback tests require IncludeLoopbackTests.'}
    if($catalog[$name] -eq 'LiveProvider' -and -not $IncludeLiveProviderChecks){throw 'Native provider inspectors require IncludeLiveProviderChecks.'}
}
$directory=Join-Path $root ('output\tests\validation-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($directory)
$revision=$null;if(Get-Command git -ErrorAction SilentlyContinue){$revision=& git -C $root rev-parse HEAD 2>$null;if($LASTEXITCODE -ne 0){$revision=$null}}
$identity=New-SnapshotIdentity
$report=[pscustomobject]@{Runtime=$PSVersionTable.PSVersion.ToString();OS=[Environment]::OSVersion.Version.ToString();OSProvenance='System.Environment.OSVersion of actual runner, not a Windows 10/11 certification';IsElevated=$identity.IsElevated;Revision=$revision;RevisionProvenance='Git HEAD when available; working tree may contain edits';Suites=@();AssertionTotal=$null}
foreach($name in $Suite){
    Write-Host "Running $name ($($catalog[$name]))"
    $path=Join-Path $PSScriptRoot ($name+'.ps1')
    $result=Invoke-BoundedCheck ([pscustomobject]@{Name=$name;FunctionName='Invoke-TestSuiteFile';Arguments=@{Path=$path}}) (Join-Path $root 'src') $directory $SuiteTimeoutSeconds -AdditionalSources @((Join-Path $PSScriptRoot 'fixtures\SuiteWorker.ps1'))
    $data=@($result.Data) | Select-Object -First 1
    $exitCode=$null;if($result.Status -eq 'Success'){$exitCode=$data.ExitCode}
    $row=[pscustomobject]@{Suite=$name;Command=('powershell.exe -NoProfile -NonInteractive -File "'+$path+'"');Category=$catalog[$name];ExitCode=$exitCode;WorkerStatus=$result.Status;DurationSeconds=$result.DurationMs/1000.0;Error=$result.Error
        ProviderCoverage=$(if($catalog[$name] -eq 'LiveProvider'){'Native'}else{'Synthetic/mocked; no native provider validation'})
        Collectors=$(if($catalog[$name] -eq 'LiveProvider'){'Native inspector queries'}else{'Synthetic fixtures or mocked collectors; see suite source for worker versus direct execution'})
        Persistence=$(if($catalog[$name] -eq 'Model'){'Modeled'}elseif($catalog[$name] -eq 'Persistence'){'Real atomic I/O'}else{'See suite source; worker/bootstrap artifacts may use real I/O'})}
    $report.Suites+=$row
    [IO.File]::WriteAllText((Join-Path $directory ($name+'.log')),[string]$data.Output)
    Write-Host "$name : worker=$($result.Status), exit=$exitCode"
}
$reportPath=Join-Path $directory 'results.json';[IO.File]::WriteAllText($reportPath,(ConvertTo-Json $report -Depth 12))
Write-Host "Validation record: $reportPath"
if(@($report.Suites | Where-Object {$_.WorkerStatus -ne 'Success' -or $null -eq $_.ExitCode -or $_.ExitCode -ne 0}).Count){exit 1}
