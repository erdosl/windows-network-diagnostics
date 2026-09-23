#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core.ps1','State.ps1','Connectivity.ps1','Events.ps1','Orchestration.ps1')) { . (Join-Path $root "src\$file") }
$script:count = 0
function Assert-Dns { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw "Assertion failed: $Message" }; $script:count++ }
function New-DnsChecks { param([object[]]$Entries)
    @([pscustomobject]@{Name='DNSServers';Status='Success';Data=$Entries},
      [pscustomobject]@{Name='Adapters';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=7;Name='VPN <lab>';Status='Disconnected';HardwareInterface=$false})},
      [pscustomobject]@{Name='InterfacesAndMetrics';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=7;AddressFamily=23;ConnectionState='Disconnected'})})
}
$entries = @()
foreach ($n in 1..3) {
    $entries += [pscustomobject]@{InterfaceIndex=7;InterfaceAlias='VPN <lab>';ServerAddresses=@("fec0:0:0:ffff::$n", "fec0:0000:0000:ffff:0000:0000:0000:000$n")}
    $entries += [pscustomobject]@{InterfaceIndex=8;InterfaceAlias='Other';ServerAddresses=@("fec0:0:0:ffff::$n")}
}
$checks = New-DnsChecks $entries
$targets = @(Get-DnsTargetInventory $checks)
Assert-Dns ($targets.Count -eq 3) 'Equivalent legacy addresses deduplicated across associations'
foreach ($t in $targets) {
    Assert-Dns ($t.Classification -eq 'LegacyDiscovery' -and $t.Selection -eq 'Skipped') 'Exact legacy target skipped'
    Assert-Dns ($t.ConfiguredAssociations.Count -eq 3 -and $t.OriginalAddresses.Count -eq 2) 'All original associations and spellings retained'
    Assert-Dns ($t.ConfiguredAssociations[0].Adapters[0].Kind -eq 'Virtual/software' -and $t.ConfiguredAssociations[0].IPInterfaceStates[0].ConnectionState -eq 'Disconnected') 'Virtual adapter and family state retained'
}
foreach ($n in 1..3) {
    $scopedChecks = New-DnsChecks @([pscustomobject]@{ InterfaceIndex=7;InterfaceAlias='Scoped';ServerAddresses=@("fec0:0000:0000:ffff:0000:0000:0000:000$n%007", "fec0:0:0:ffff::$n%7") })
    $scopedTargets = @(Get-DnsTargetInventory $scopedChecks)
    Assert-Dns ($scopedTargets.Count -eq 1 -and $scopedTargets[0].Classification -eq 'LegacyDiscovery' -and $scopedTargets[0].ConfiguredAssociations.Count -eq 2) 'Every scoped legacy form uses parsed equality and retains original zones'
}
$ambiguous = New-DnsChecks @([pscustomobject]@{InterfaceIndex=7;ServerAddresses=@('fe80::53')},[pscustomobject]@{InterfaceIndex=8;ServerAddresses=@('fe80::53')})
Assert-Dns (@(Get-DnsTargetInventory $ambiguous).Count -eq 2) 'Unzoned link-local targets on different configured interfaces are not merged'
$other = New-DnsChecks @([pscustomobject]@{InterfaceIndex=7;InterfaceAlias='VPN';ServerAddresses=@('fec0::4','fec0:0:0:ffff::4','fe80::53%7','fe80:0:0:0:0:0:0:53%8','fec0:0:0:ffff::1%7','fe80::54')})
$more = @(Get-DnsTargetInventory $other)
Assert-Dns (@($more | Where-Object Classification -eq LegacyDiscovery).Count -eq 1) 'Other fec0 addresses are not legacy'
Assert-Dns (@($more | Where-Object Selection -eq Selected).Count -eq 5) 'VPN and no-default-route targets remain eligible'
Assert-Dns (@($more | Where-Object Server -like 'fe80::*%*').Count -eq 2) 'Different explicit IPv6 zones stay distinct'
Assert-Dns (($more | Where-Object Server -eq 'fe80::54').ScopeUncertainty.Count -gt 0 -and ($more | Where-Object Server -eq 'fe80::54').Server -notmatch '%') 'Missing zone is recorded, not invented'
$scoped = $more | Where-Object Classification -eq LegacyDiscovery
Assert-Dns ($scoped.ScopeId -eq '7' -and $scoped.OriginalAddresses[0] -eq 'fec0:0:0:ffff::1%7') 'Scoped legacy classification preserves scope'
Assert-Dns (@(Get-DnsTargetInventory $checks $true | Where-Object Selection -eq Selected).Count -eq 3) 'Explicit legacy opt-in selects targets'
foreach ($case in @(@(1460,'Timeout'),@(10060,'Timeout'),@(9003,'NameError/NXDOMAIN'),@(9002,'ServerFailure'),@(9005,'Refused'),@(9999,'Unknown'))) {
    $ex = [ComponentModel.Win32Exception]::new([int]$case[0], 'Zeitlimit der Anfrage wurde erreicht')
    $record = [Management.Automation.ErrorRecord]::new($ex,'SyntheticId',[Management.Automation.ErrorCategory]::NotSpecified,$null)
    $detail = Get-DnsErrorDetail $record
    Assert-Dns ($detail.Classification -eq $case[1] -and $detail.NumericCodes.Count -gt 0 -and $detail.FullyQualifiedErrorId -eq 'SyntheticId') "Structured code $($case[0])"
}
$wrapped = [Exception]::new('Wrapper', [ComponentModel.Win32Exception]::new(9005,'Requete refusee'))
$record = [Management.Automation.ErrorRecord]::new($wrapped,'Wrapped',[Management.Automation.ErrorCategory]::NotSpecified,$null)
Assert-Dns ((Get-DnsErrorDetail $record).Classification -eq 'Refused') 'Inner native exception is preserved and classified'
$hr = [Runtime.InteropServices.COMException]::new('Nom absent', -2147015893)
$record = [Management.Automation.ErrorRecord]::new($hr,'WrappedHResult',[Management.Automation.ErrorCategory]::NotSpecified,$null)
Assert-Dns ((Get-DnsErrorDetail $record).Classification -eq 'NameError/NXDOMAIN') 'HRESULT_FROM_WIN32 decoded without arbitrary low-bit guessing'
$record = [Management.Automation.ErrorRecord]::new([Exception]::new('NXDOMAIN timeout refused'),'DNS_ERROR_RCODE_NAME_ERROR',[Management.Automation.ErrorCategory]::NotSpecified,$null)
Assert-Dns ((Get-DnsErrorDetail $record).Classification -eq 'Unknown') 'Message and identifier alone do not invent numeric causes'
function Find-NetRoute { [CmdletBinding()]param($RemoteIPAddress); throw 'Synthetic route unavailable' }
function Resolve-DnsName { [CmdletBinding()]param($Name,$Type,$Server,[switch]$DnsOnly,[switch]$NoHostsFile,[switch]$QuickTimeout); throw [ComponentModel.Win32Exception]::new(1460,'Different language') }
$probe = Invoke-ConnectivityProbe DNS '192.0.2.53'
Assert-Dns ($probe.Outcome -eq 'TimedOut' -and $probe.TimeoutScope -eq 'DNS' -and $probe.DnsError.Code -eq 1460) 'DNS timeout mapped without English matching'
function Resolve-DnsName { [CmdletBinding()]param($Name,$Type,$Server,[switch]$DnsOnly,[switch]$NoHostsFile,[switch]$QuickTimeout) }
Assert-Dns ((Invoke-ConnectivityProbe DNS '192.0.2.53').Outcome -eq 'Success') 'Empty answer set is not NXDOMAIN'
$workspace = Join-Path $root ('output\tests\dns-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force $workspace
# Mock only persistence for orchestration; no worker/network calls are made.
$realWriter = ${function:Write-DiagnosticReport}
function Write-DiagnosticReport { param($Evidence,$OutputDirectory) }
$script:activeCalls = 0
$executor = {
    param($definition,$timeout,$directory)
    if ($definition.FunctionName -eq 'Invoke-ConnectivityProbe') { $script:activeCalls++ }
    $data = @()
    if ($definition.Name -eq 'DNSServers') { $data = $entries }
    [pscustomobject]@{Name=$definition.Name;Status='Success';Data=$data;Request=$definition.Arguments;Error=$null}
}
$passive = Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $workspace -CheckExecutor $executor
Assert-Dns ($script:activeCalls -eq 0) 'No active probes by default'
$rejected = $false
try { $null = Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $workspace -IncludeLegacyDnsTargets -CheckExecutor $executor } catch { $rejected = $_.Exception.Message -match 'requires IncludeConnectivityTests' }
Assert-Dns $rejected 'Inconsistent switches rejected before any collection'
$run = Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $workspace -IncludeConnectivityTests -CheckExecutor $executor
$rows = @(Get-DnsResultSummary $run.Evidence.Checks)
Assert-Dns ($rows.Count -eq 6 -and @($rows | Where-Object ProbeOutcome -eq Skipped).Count -eq 6 -and $script:activeCalls -eq 3) 'Legacy queries skipped in parent, never sent to executor'
Assert-Dns ($rows[0].SelectionReason -eq 'Legacy DNS discovery address; operational use unconfirmed.') 'Clear skip reason'
$opt = Invoke-SnapshotRun -RepositoryRoot $root -TestOutputRoot $workspace -IncludeConnectivityTests -IncludeLegacyDnsTargets -CheckExecutor $executor
Assert-Dns ($script:activeCalls -eq 12) 'Opt-in legacy queries sent through ordinary executor'
${function:Write-DiagnosticReport} = $realWriter
$worker = [pscustomobject]@{Name='Connectivity:DNS:worker';Status='TimedOut';Data=@();Request=@{Kind='DNS';Destination='192.0.2.53';QueryName='test.invalid';QueryType='A'}}
$row = Get-DnsResultSummary @($worker)
Assert-Dns ($row.TimeoutScope -eq 'Worker' -and $row.ProbeOutcome -eq 'Unknown' -and -not $row.DnsErrorClassification) 'Worker timeout is not DNS timeout'
$run.Evidence.Checks += $worker
$run.Evidence.Checks | Where-Object Status -eq Skipped | ForEach-Object { $_.Data[0].DnsTarget.Reason = '<reason>'; $_.Data[0].Evidence.QueryName = '<query>' }
$paths = Write-DiagnosticReport $run.Evidence (Join-Path $workspace 'html')
$html = Get-Content -Raw $paths.HtmlPath
Assert-Dns ($html.Contains('Skipped=6') -and $html.Contains('&lt;reason&gt;') -and $html.Contains('&lt;query&gt;') -and $html.Contains('&lt;lab&gt;') -and -not $html.Contains('<reason>')) 'DNS table encodes associations/reasons/query and counts skips'
Assert-Dns ($run.Evidence.Findings.Hypotheses.Count -eq 0) 'Legacy failures/skips do not diagnose DNS fault'
Write-Host "PASS: $script:count DNS assertions; synthetic only."
