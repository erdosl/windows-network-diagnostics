#requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(10,600)][int]$DurationSeconds=60,[ValidateRange(5,120)][int]$IntervalSeconds=10,
    [ValidateRange(1,60)][int]$CheckTimeoutSeconds=10,[string]$IncidentContextPath)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Execution','Events','Collection','Observation')){. (Join-Path $PSScriptRoot "src\$file.ps1")}
Invoke-ObservationRun -RepositoryRoot $PSScriptRoot @PSBoundParameters
