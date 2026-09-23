#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1,168)][int]$LookbackHours = 24,
    [ValidateRange(1,1000)][int]$MaxEventsPerLog = 200,
    [ValidateRange(1,1000)][int]$MaxNicEvents = 200,
    [ValidateRange(1,1000)][int]$MaxPowerEvents = 100,
    [ValidateRange(1,600)][int]$CheckTimeoutSeconds = 30,
    [switch]$IncludeConnectivityTests,
    [switch]$IncludeGatewayPing,
    [ValidateCount(1,16)][string[]]$TcpDestinations = @('1.1.1.1','2606:4700:4700::1111'),
    [ValidateRange(1,65535)][int]$TcpPort = 443,
    [string]$DnsQueryName = 'example.com',
    [string]$HttpsEndpoint = 'https://example.com/',
    [ValidateRange(1,60)][int]$ProbeTimeoutSeconds = 10,
    [ValidateRange(5,120)][int]$ProbeWorkerOverheadSeconds = 15
)
$ErrorActionPreference = 'Stop'
foreach ($file in @('Core.ps1','State.ps1','Execution.ps1','Events.ps1','Collection.ps1','Connectivity.ps1','Orchestration.ps1')) {
    . (Join-Path (Join-Path $PSScriptRoot 'src') $file)
}
if ($env:OS -ne 'Windows_NT') { throw 'This collector requires Windows 10/11.' }
$paths = Invoke-SnapshotRun -RepositoryRoot $PSScriptRoot @PSBoundParameters
Get-CheckSummary -Checks $paths.Evidence.Checks | Format-Table Name,CollectionStatus,ProbeOutcome,TimeoutScope -AutoSize -Wrap | Out-Host
Write-Host "JSON evidence: $($paths.JsonPath)"
Write-Host "HTML summary:  $($paths.HtmlPath)"
$paths | Select-Object JsonPath,HtmlPath
