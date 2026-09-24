#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateCount(1,4)][guid[]]$AdapterGuid,
    [ValidateRange(5,300)][int]$DurationSeconds=30,[ValidateRange(1,64)][int]$MaxSizeMB=16,[switch]$IncludeArp)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Execution','Capture')){. (Join-Path $PSScriptRoot "src\$file.ps1")}
$result=Invoke-CaptureRequest -RepositoryRoot $PSScriptRoot @PSBoundParameters
$result
Write-Warning $result.Evidence.Explanation
exit 2
