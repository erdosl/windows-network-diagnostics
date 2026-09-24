#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core.ps1','State.ps1','Execution.ps1','Events.ps1','Collection.ps1','Connectivity.ps1','Orchestration.ps1')) {
    . (Join-Path (Join-Path $root 'src') $file)
}
$script:count = 0
function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:count++
}
$workspace = Join-Path $root ('output\tests\milestone2-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $workspace

# A real process timeout, a native child, and a subsequent successful worker.
$fixture = Join-Path $PSScriptRoot 'fixtures\Collectors.ps1'
$definition = [pscustomobject]@{ Name = 'Sleep'; FunctionName = 'Invoke-TestCollector'; Arguments = @{
    Mode = 'SleepWithChild'; MarkerRoot = $workspace; ChildScript = (Join-Path $PSScriptRoot 'fixtures\Delayed-Write.ps1') } }
$timed = Invoke-BoundedCheck $definition (Join-Path $root 'src') $workspace -TimeoutSeconds 5 -AdditionalSources @($fixture)
Assert-Condition ($timed.Status -eq 'TimedOut') 'Worker hits distinct timeout status'
$workerSummary = @(Get-CheckSummary @([pscustomobject]@{ Name = 'Connectivity:TCP'; Status = $timed.Status; Data = $timed.Data }))[0]
Assert-Condition ($workerSummary.CollectionStatus -eq 'TimedOut' -and $workerSummary.TimeoutScope -eq 'Worker' -and $workerSummary.ProbeOutcome -like 'Unknown*') 'Worker timeout is not a network outcome'
Assert-Condition ($timed.DurationMs -lt 12000) 'Timeout cleanup is bounded'
Assert-Condition (Test-Path (Join-Path $workspace 'child-pid.txt')) 'Worker actually started a child before timeout'
$childId = [int](Get-Content (Join-Path $workspace 'child-pid.txt'))
Assert-Condition ($null -eq (Get-Process -Id $timed.WorkerProcessId -ErrorAction SilentlyContinue)) 'Worker stopped before returning'
Assert-Condition ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Descendant stopped before returning'
Start-Sleep -Seconds 9
Assert-Condition (-not (Test-Path (Join-Path $workspace 'late-write.txt'))) 'Timed-out descendants cannot write later'
Assert-Condition (@(Get-ChildItem $workspace -Directory -Filter '.worker-*').Count -eq 0) 'Private scratch cleaned'
$definition = [pscustomobject]@{ Name = 'Echo'; FunctionName = 'Invoke-TestCollector'; Arguments = @{ Mode = 'Echo'; Value = 'explicit payload' } }
$good = Invoke-BoundedCheck $definition (Join-Path $root 'src') $workspace -TimeoutSeconds 15 -AdditionalSources @($fixture)
Assert-Condition ($good.Status -eq 'Success' -and $good.Data[0].Value -eq 'explicit payload') 'Next worker succeeds without caller-scope inputs'
$enumRoundtrip = ConvertTo-Json -InputObject $good -Depth 12 | ConvertFrom-Json
Assert-Condition ($enumRoundtrip.Data[0].EnumValue -eq 2) 'Enum worker results remain JSON-readable without CLIXML value/Value collisions'
$definition.Arguments.Mode = 'Fail'
$bad = Invoke-BoundedCheck $definition (Join-Path $root 'src') $workspace -TimeoutSeconds 15 -AdditionalSources @($fixture)
Assert-Condition ($bad.Status -eq 'Failed' -and $bad.Error.Message -match 'Synthetic worker failure') 'Worker errors serialized'

# Full parent orchestration with mocked passive/event/probe collectors.
$script:executed = @()
. (Join-Path $PSScriptRoot 'fixtures\Milestone2Orchestration.ps1')
$script:checkpoints = @()
$observer = { param($evidence, $directory)
    $saved = Read-DiagnosticEvidence (Join-Path $directory 'evidence.json')
    $script:checkpoints += [pscustomobject]@{ Status = $saved.CollectionStatus; Count = $saved.Checks.Count; End = $saved.CompletedAt; TimeoutCount=@($saved.Checks | Where-Object Status -eq 'TimedOut').Count }
}
$run = Invoke-SnapshotRun -TestOutputRoot (Join-Path $root 'output\tests\orchestration') -RepositoryRoot $root -CheckExecutor $mock -CheckpointObserver $observer
Assert-Condition ($run.Evidence.SchemaVersion -eq 9 -and $run.Evidence.CollectionStatus -eq 'Complete') 'Versioned completed snapshot'
Assert-Condition ($run.Evidence.ComputerName -eq [Environment]::MachineName) 'Computer identity'
$id = [guid]::Empty
Assert-Condition ([guid]::TryParse($run.Evidence.RunId, [ref]$id)) 'Unique RunId is a GUID'
Assert-Condition ($run.JsonPath.Contains($run.Evidence.RunId) -and $run.JsonPath.Contains($run.Evidence.ComputerName)) 'Output path includes run and computer'
Assert-Condition ($run.Evidence.CollectorVersion -eq '0.5.3' -and $run.Evidence.IsElevated -is [bool]) 'Version and process elevation'
Assert-Condition ($run.Evidence.StartedAt -match '[+-]\d\d:\d\d$' -and $run.Evidence.CompletedAt -match '[+-]\d\d:\d\d$') 'Collection timestamps retain UTC offsets'
Assert-Condition ($script:checkpoints[0].Status -eq 'Incomplete' -and $script:checkpoints[0].Count -eq 0) 'Checkpoint exists before first check'
Assert-Condition (@($script:checkpoints | Where-Object { $_.Status -eq 'Incomplete' -and $_.Count -gt 0 }).Count -gt 0) 'Completed checks saved incrementally'
Assert-Condition (@($script:executed | Where-Object FunctionName -eq 'Invoke-ConnectivityProbe').Count -eq 0) 'No active operations by default'
$savedFinal=Get-Content -LiteralPath $run.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Milestone2Continuation -Evidence $run.Evidence -Executed $script:executed -Saved $savedFinal
Assert-Condition (@($script:checkpoints | Where-Object {$_.Status -eq 'Incomplete' -and $_.Count -eq 1 -and $_.TimeoutCount -eq 1}).Count -gt 0) 'Timeout saved before later checks execute'
Assert-Condition ($script:checkpoints[-1].Status -eq 'Complete' -and $script:checkpoints[-1].TimeoutCount -eq 1 -and $script:checkpoints[-1].End -eq $savedFinal.CompletedAt) 'Final persisted checkpoint preserves timeout and completion'
$summary = @(Get-InterfaceSummary $run.Evidence.Checks)
Assert-Condition ($summary.Count -eq 1 -and $summary[0].Addresses.Count -eq 2 -and $summary[0].DefaultRoutes.Count -eq 2) 'Correlates multiple addresses and routes'
Assert-Condition ($summary[0].DefaultRoutes[0].InterfaceMetrics[0].InterfaceMetric -eq 25) 'Metrics joined by interface and family'
$missing = @(Get-InterfaceSummary @($run.Evidence.Checks | Where-Object Name -ne 'Adapters'))
Assert-Condition ($missing.Count -eq 1 -and $missing[0].SourceStatus.Adapters -eq 'NotCollected') 'Missing adapters do not discard other interface evidence'
$limits = @(Get-EventDefinitions -StartTime (Get-Date).AddHours(-1) -EndTime (Get-Date) -NetworkLimit 11 -NicLimit 7 -PowerLimit 3 -NicServices @('AnotherDriver'))
Assert-Condition ($limits[0].Arguments.MaxEvents -eq 11 -and $limits[1].Arguments.MaxEvents -eq 7 -and $limits[2].Arguments.MaxEvents -eq 3) 'Independent event budgets'
Assert-Condition ($limits[1].Arguments.Providers -contains 'AnotherDriver') 'NIC providers derived from driver services'

$script:executed = @()
$active = Invoke-SnapshotRun -TestOutputRoot (Join-Path $root 'output\tests\orchestration') -RepositoryRoot $root -CheckExecutor $mock -IncludeConnectivityTests -IncludeGatewayPing -TcpDestinations @('synthetic.invalid')
foreach ($kind in @('Gateway','DNS','TCP','HTTPS')) {
    Assert-Condition (@($active.Evidence.Checks | Where-Object { $_.Request.Kind -eq $kind -and $_.Data[0].Outcome -eq 'Failed' }).Count -gt 0) "Simulated $kind failure retained"
}
Assert-Condition ($active.Evidence.Findings.Hypotheses.Count -eq 0) 'Failed probes do not manufacture DNS/unreachable/root-cause diagnoses'
Assert-Condition (@($script:executed | Where-Object { $_.Arguments.Destination -eq '2001:db8::8' }).Count -gt 0) 'IPv6 probes remain separate'
Assert-Condition ($active.Evidence.RunId -ne $run.Evidence.RunId) 'Each run gets a new identity'

$interrupt = { param($evidence, $directory) if ($evidence.Checks.Count -eq 2) { $script:interruptedDirectory = $directory; throw 'Synthetic interruption' } }
$interrupted = $false
try { $null = Invoke-SnapshotRun -TestOutputRoot (Join-Path $root 'output\tests\orchestration') -RepositoryRoot $root -CheckExecutor $mock -CheckpointObserver $interrupt } catch { $interrupted = $true }
$partialPath = Join-Path $script:interruptedDirectory 'evidence.json'
$partial = Read-DiagnosticEvidence $partialPath
Assert-Condition ($interrupted -and $partial.CollectionStatus -eq 'Incomplete' -and $null -eq $partial.CompletedAt -and $partial.Checks.Count -eq 2) 'Interrupted collection retains completed checks and incomplete identity'
[IO.File]::WriteAllText($partialPath, '{broken')
$recovered = Read-DiagnosticEvidence $partialPath
Assert-Condition ($recovered.CollectionStatus -eq 'Incomplete' -and $recovered.RecoveryNote) 'Previous atomic checkpoint recovers a damaged primary'
Assert-Condition (@(Get-ChildItem $script:interruptedDirectory -Filter '*.tmp').Count -eq 0) 'Atomic writes leave no temporary files on success'

# Every new identity, interface and request field must be inert in HTML.
$hostile = '<img src=x onerror=alert(1)><script>bad()</script>&"'
foreach ($field in @('ComputerName','RunId','CollectorVersion','SchemaVersion','IsElevated','PowerShellVersion','StartedAt','CompletedAt','CollectionStatus','PendingCheck','Revision','CollectionError')) { $run.Evidence.$field = $hostile }
$run.Evidence.Parameters.HttpsEndpoint = $hostile
$run.Evidence.Checks = @([pscustomobject]@{ Name = 'Adapters'; Status = 'Success'; Data = @([pscustomobject]@{
    InterfaceIndex = $hostile; Name = $hostile; InterfaceDescription = $hostile; Status = $hostile; MacAddress = $hostile; LinkSpeed = $hostile
}); Error = $null; Request = @{ Destination = $hostile; Endpoint = $hostile } })
$htmlPaths = Write-DiagnosticReport $run.Evidence (Join-Path $workspace 'html')
$html = Get-Content $htmlPaths.HtmlPath -Raw -Encoding UTF8
Assert-Condition ($html -notmatch '<script>|<img' -and $html.Contains([Net.WebUtility]::HtmlEncode($hostile))) 'All newly rendered dynamic fields encoded'
$json = Get-Content $htmlPaths.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($json.ComputerName -ceq $hostile -and $json.Checks[0].Request.Endpoint -ceq $hostile) 'Raw JSON is preserved without HTML mutations'
Write-Host "PASS: $script:count milestone 2 assertions on Windows PowerShell $($PSVersionTable.PSVersion)."
