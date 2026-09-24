#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PreviousSnapshotPath,
    [string]$ExpectationsPath,
    [string]$IncidentContextPath,
    [ValidateRange(1,168)][int]$LookbackHours = 24,
    [ValidateRange(1,1000)][int]$MaxEventsPerLog = 200,
    [ValidateRange(1,1000)][int]$MaxNicEvents = 200,
    [ValidateRange(1,1000)][int]$MaxPowerEvents = 100,
    [ValidateRange(1,600)][int]$CheckTimeoutSeconds = 30,
    [switch]$IncludeConnectivityTests,
    [switch]$IncludeGatewayPing,
    [switch]$IncludeLegacyDnsTargets,
    [ValidateRange(1,16777215)][int]$ProbeInterfaceIndex,
    [string]$ProbeSourceAddress,
    [ValidateRange(1,64)][int]$MaxInterfaceProbes=16,
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
$missingProviders = @($paths.Evidence.Checks | Where-Object { $_.Error.Explanation -eq 'No matching adapter-provider object was returned.' })
if ($missingProviders.Count) { Write-Host ("{0} adapter checks unavailable: No matching adapter-provider object was returned. This does not establish faulty or unsupported hardware." -f $missingProviders.Count) }
$consoleWidth = 80
try { if ($Host.UI.RawUI.WindowSize.Width -ge 20) { $consoleWidth = $Host.UI.RawUI.WindowSize.Width } } catch { }
Format-DnsConsoleReport $paths.Evidence.Checks -Width ([Math]::Min(1000, $consoleWidth)) | ForEach-Object { Write-Host $_ }
$map = $paths.Evidence.LogicalNetwork
Write-Host ("Logical map: {0} interfaces, {1} interface-scoped subnets, {2} neighbour observations ({3} eligible endpoint observations, not physical devices)." -f $map.Counts.Interfaces,$map.Counts.Subnets,$map.Counts.NeighbourObservations,$map.Counts.EligibleEndpointObservations)
Write-Host 'Physical Layer 2 paths unknown; structured Wi-Fi association unavailable.'
Write-Host 'Competing DHCP servers: not assessed.'
Write-Host ("Snapshot comparison: {0}; expectations: {1}. See HTML for details." -f $paths.Evidence.SnapshotComparison.Status,$paths.Evidence.ExpectationAssessment.Status)
$gaps = @($map.Coverage | Where-Object { $_.Status -ne 'Success' })
Write-Host ("Coverage: {0} unavailable, failed, uncollected or unknown sources; see HTML for details." -f $gaps.Count)
Write-Host "JSON evidence: $($paths.JsonPath)"
Write-Host "HTML summary:  $($paths.HtmlPath)"
$paths | Select-Object JsonPath,HtmlPath
