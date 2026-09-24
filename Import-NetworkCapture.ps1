#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,10000)][int]$MaxPackets=10000)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Capture')){. (Join-Path $PSScriptRoot "src\$file.ps1")}
$directory=Join-Path $PSScriptRoot ('output\capture-import-'+[guid]::NewGuid().ToString('N'))
Import-CaptureEvidence -Path $Path -OutputDirectory $directory -MaxPackets $MaxPackets
Write-Host "Local capture evidence: $directory"
