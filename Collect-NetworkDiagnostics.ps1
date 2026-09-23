#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1,168)][int]$LookbackHours = 24,
    [ValidateRange(1,1000)][int]$MaxEventsPerLog = 200
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Core.ps1')
. (Join-Path $PSScriptRoot 'src\Collection.ps1')
if ($env:OS -ne 'Windows_NT') { throw 'This collector requires Windows 10/11.' }
$snapshot = Get-NetworkSnapshot -LookbackHours $LookbackHours -MaxEventsPerLog $MaxEventsPerLog
$runName = 'snapshot-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$destination = Join-Path (Join-Path $PSScriptRoot 'output') $runName
$paths = Write-DiagnosticReport -Evidence $snapshot -OutputDirectory $destination
$snapshot.Checks | Select-Object Name, Status | Format-Table -AutoSize | Out-Host
Write-Host "JSON evidence: $($paths.JsonPath)"
Write-Host "HTML summary:  $($paths.HtmlPath)"
$paths
