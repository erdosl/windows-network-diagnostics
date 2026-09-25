#requires -Version 5.1

<#
.SYNOPSIS
Collect a bounded passive observation with immutable samples and an offline summary.
.DESCRIPTION
No active probes or capture. Canonical or HTML finalization failure terminates
with exit 1; earlier checkpoints, samples and backups remain recoverable.
Analysis and collection outcomes are reported separately from publication.
.PARAMETER OutputRoot
Output parent relative to the caller's working directory; default is repository output.
.EXAMPLE
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 60 -OutputRoot 'C:\temp\Network reports'
#>
[CmdletBinding()]
param([ValidateRange(10,600)][int]$DurationSeconds=60,[ValidateRange(5,120)][int]$IntervalSeconds=10,
    [ValidateRange(1,60)][int]$CheckTimeoutSeconds=10,[string]$IncidentContextPath,[string]$OutputRoot)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Execution','Events','Collection','Observation')){. (Join-Path $PSScriptRoot "src\$file.ps1")}
Invoke-ObservationRun -RepositoryRoot $PSScriptRoot @PSBoundParameters
