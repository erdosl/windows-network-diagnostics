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
$models=@('Test-AdditionalOrchestrationModel','Test-ObservationModel','Test-LiveObservation','Test-CaptureEvidence','Test-Milestone2Continuation','Test-Windows11Evidence','Test-ReliabilityModel','Test-AnalysisIsolation','Test-EventCoverage')
$workers=@('Test-Windows11Worker','Test-InventoryBoundaries','Test-EntryLoading','Test-OutputPlacement','Test-Verification','Test-RunnerRecovery','Test-DnsPolicy')
$persistence=@('Test-Snapshot','Test-AdapterApipa','Test-DhcpContext','Test-DhcpReview','Test-SnapshotComparison','Test-EventCorrelation','Test-LogicalNetwork','Test-Dns','Test-Milestone2','Test-DhcpOrchestration','Test-ObservationRun','Test-CaptureImport','Test-PathPortability','Test-LongCheckout','Test-ReliabilityPersistence')
$synthetic=@('Test-AdditionalEvidence','Test-CaptureVlan','Test-InterfaceProbes','Test-Observation','Test-ObservationDhcp','Test-ObservationSerialization','Test-Presentation','Test-LeaseReliability','Test-ErrorClassification','Test-SourceSyntax','Test-HttpParsing','Test-ObservationFields')
$catalog=@{}
foreach($pair in @(@('Model',$models),@('Worker',$workers),@('Persistence',$persistence),@('Synthetic',$synthetic),@('Loopback',@('Test-Probes','Test-ProbeReview')),@('LiveProvider',@('Inspect-Windows11Providers')))){
    foreach($name in $pair[1]){$catalog[$name]=$pair[0]}
}
. (Join-Path $PSScriptRoot 'RunnerCore.ps1')
Test-SuiteCatalog $PSScriptRoot $catalog
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

$report=Invoke-ValidationCatalog -Root $root -SuiteDirectory $PSScriptRoot -Suite $Suite -Catalog $catalog -Directory $directory -TimeoutSeconds $SuiteTimeoutSeconds -Report $report
if(@($report.Suites | Where-Object {$_.WorkerStatus -ne 'Success' -or $null -eq $_.ExitCode -or $_.ExitCode -ne 0}).Count){exit 1}
