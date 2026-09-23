#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core.ps1','State.ps1','Connectivity.ps1')) { . (Join-Path $root "src\$file") }
$script:count = 0
function Assert-Review { param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }; $script:count++
}
function Find-NetRoute { [CmdletBinding()] param($RemoteIPAddress); throw 'Synthetic route unavailable' }
function Get-NetIPAddress { [CmdletBinding()] param($IPAddress); [pscustomobject]@{ IPAddress = $IPAddress; InterfaceIndex = 1 } }
function Resolve-DnsName { [CmdletBinding()] param($Name,$Type,$Server,[switch]$DnsOnly,[switch]$NoHostsFile,[switch]$QuickTimeout); throw 'Synthetic DNS failure' }
$dns = Invoke-DiagnosticCheck 'Connectivity:DNS' { Invoke-ConnectivityProbe DNS '192.0.2.53' }
$rows = @(Get-CheckSummary @($dns))
Assert-Review ($rows[0].CollectionStatus -eq 'Success' -and $rows[0].ProbeOutcome -eq 'Failed') 'Completed DNS failure is not working connectivity'
# Deterministic exception simulation, independent of firewall timing on a refused port.
$originalTcpFactory = ${function:New-ProbeTcpClient}
function New-ProbeTcpClient {
    param($AddressFamily)
    $client = [pscustomobject]@{}
    $client | Add-Member ScriptMethod BeginConnect { param($Address,$Port,$Callback,$State)
        [pscustomobject]@{ AsyncWaitHandle = [Threading.ManualResetEvent]::new($true) }
    }
    $client | Add-Member ScriptMethod EndConnect { param($AsyncResult); throw [Net.Sockets.SocketException]::new(10061) }
    $client | Add-Member ScriptMethod Close { }
    $client
}
$refused = Invoke-DiagnosticCheck 'Connectivity:TCP' { Invoke-ConnectivityProbe TCP '127.0.0.1' -TimeoutMs 2000 }
Assert-Review ($refused.Status -eq 'Success' -and $refused.Data[0].Outcome -eq 'Failed' -and $refused.Data[0].Error -and -not $refused.Data[0].ObservedConnection) 'Refused TCP remains a failed probe, with no invented path'
${function:New-ProbeTcpClient} = $originalTcpFactory
# Real loopback TCP, mocked TLS/HTTP only; no certificate overrides or external connections.
function New-ProbeTlsStream {
    param($Stream)
    $fake = [pscustomobject]@{ SslProtocol = 'SyntheticTLS'; WriteTimeout = 0; ReadTimeout = 0; Position = 0; Text = "HTTP/1.1 503 Unavailable`r`n" }
    $fake | Add-Member ScriptMethod Write { param($Bytes,$Offset,$Count) }
    $fake | Add-Member ScriptMethod Dispose { }
    $fake | Add-Member ScriptMethod ReadByte { $value = [int][char]$this.Text[$this.Position]; $this.Position++; $value }
    $fake
}
function Invoke-ProbeTlsHandshake { param($Stream,$HostName,$Watch,$TimeoutMs); throw [Security.Authentication.AuthenticationException]::new('Synthetic TLS validation failure') }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
try {
    $tls = Invoke-DiagnosticCheck 'Connectivity:HTTPS:TLS' { Invoke-ConnectivityProbe HTTPS '127.0.0.1' -Port $listener.LocalEndpoint.Port -Endpoint 'https://localhost/' -TimeoutMs 2000 }
    Assert-Review ($tls.Status -eq 'Success' -and $tls.Data[0].Outcome -eq 'Failed' -and $tls.Data[0].ObservedConnection -and $tls.Data[0].CompletedStages -contains 'TCP connect') 'TLS failure retains successful TCP evidence'
    function Invoke-ProbeTlsHandshake { param($Stream,$HostName,$Watch,$TimeoutMs) }
    $http = Invoke-DiagnosticCheck 'Connectivity:HTTPS:HTTP' { Invoke-ConnectivityProbe HTTPS '127.0.0.1' -Port $listener.LocalEndpoint.Port -Endpoint 'https://localhost/' -TimeoutMs 2000 }
    Assert-Review ($http.Status -eq 'Success' -and $http.Data[0].Outcome -eq 'HttpError' -and $http.Data[0].Evidence.HttpStatusLine -match '503') 'HTTP error retained despite successful collection'
    function Invoke-ProbeTlsHandshake { param($Stream,$HostName,$Watch,$TimeoutMs); Start-Sleep -Milliseconds 250 }
    $timeout = Invoke-DiagnosticCheck 'Connectivity:HTTPS:Timeout' { Invoke-ConnectivityProbe HTTPS '127.0.0.1' -Port $listener.LocalEndpoint.Port -Endpoint 'https://localhost/' -TimeoutMs 200 }
    Assert-Review ($timeout.Status -eq 'Success' -and $timeout.Data[0].Outcome -eq 'TimedOut' -and $timeout.Data[0].TimeoutScope -eq 'Probe') 'Probe budget exhaustion differs from worker timeout'
    Assert-Review ($timeout.Data[0].ObservedConnection -and $timeout.Data[0].CompletedStages -contains 'TLS negotiation' -and $timeout.Data[0].Evidence.TlsProtocol -eq 'SyntheticTLS') 'Completed stages survive ordinary timeout'
} finally { $listener.Stop() }
$watch = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Milliseconds 80
$remaining = Get-ProbeRemainingMilliseconds $watch 200 'second stage'
Assert-Review ($remaining -lt 160 -and $remaining -gt 0) 'Second stage receives only remaining budget'
# A slow response must not renew the allowance for every byte.
$slow = [pscustomobject]@{ ReadTimeout = 0 }
$slow | Add-Member ScriptMethod ReadByte { Start-Sleep -Milliseconds 60; 65 }
$watch.Restart()
$expired = $false
try { $null = Read-ProbeHttpStatus $slow $watch 150 } catch { $expired = $_.Exception -is [TimeoutException] }
Assert-Review ($expired -and $watch.ElapsedMilliseconds -lt 1000) 'Slow HTTP bytes cannot extend shared deadline indefinitely'
$worker = [pscustomobject]@{ Name = 'Connectivity:Worker'; Status = 'TimedOut'; Data = @() }
$row = Get-CheckSummary @($worker)
Assert-Review ($row.CollectionStatus -eq 'TimedOut' -and $row.ProbeOutcome -like 'Unknown*' -and $row.TimeoutScope -eq 'Worker') 'No fabricated probe outcome after killed worker'
$hostile = [pscustomobject]@{ Name = '<check>'; Status = '<status>'; Data = @([pscustomobject]@{ Outcome = '<outcome>'; TimeoutScope = '<scope>' }) }
$checks = @($dns,$refused,$tls,$http,$timeout,$worker,$hostile)
$evidence = [pscustomobject]@{ Checks = $checks; Findings = Get-DiagnosticFindings $checks }
$directory = Join-Path $root ('output\review-tests-' + [guid]::NewGuid().ToString('N'))
$paths = Write-DiagnosticReport $evidence $directory
$html = Get-Content -Raw $paths.HtmlPath
Assert-Review ($html -match '<th>CollectionStatus</th><th>ProbeOutcome</th>' -and $html -match '<td>Success</td><td>HttpError</td>' -and $html -match '<td>Success</td><td>Failed</td>') 'HTML prominently separates successful collection from failed tests'
foreach ($value in @('check','status','outcome','scope')) { Assert-Review ($html.Contains("&lt;$value&gt;") -and -not $html.Contains("<$value>")) 'Every summary field is escaped' }
Assert-Review ($evidence.Findings.Hypotheses.Count -eq 0) 'Probe failures are not diagnoses'
# Real isolated workers: a normal deadline returns evidence; a stalled worker is killed.
. (Join-Path $root 'src\Execution.ps1')
$fixture = Join-Path $PSScriptRoot 'fixtures\ProbeBudget.ps1'
$definition = [pscustomobject]@{ Name = 'Connectivity:TCP'; FunctionName = 'Invoke-ReviewDeadlineProbe'; Arguments = @{} }
$bounded = Invoke-BoundedCheck $definition (Join-Path $root 'src') $directory -TimeoutSeconds 10 -AdditionalSources @($fixture)
Assert-Review ($bounded.Status -eq 'Success' -and $bounded.Data[0].Outcome -eq 'TimedOut' -and $bounded.Data[0].TimeoutScope -eq 'Probe') 'Worker startup does not consume the internal probe allowance; timed-out result is written'
$definition.FunctionName = 'Invoke-ReviewStalledProbe'
$stalled = Invoke-BoundedCheck $definition (Join-Path $root 'src') $directory -TimeoutSeconds 2 -AdditionalSources @($fixture)
Assert-Review ($stalled.Status -eq 'TimedOut' -and $stalled.TimeoutScope -eq 'Worker' -and $stalled.Data.Count -eq 0) 'Hard worker timeout retains no fabricated completed probe'
Assert-Review (-not (Get-Process -Id $stalled.WorkerProcessId -ErrorAction SilentlyContinue)) 'Timed-out worker has exited'
$definition.FunctionName = 'Invoke-ReviewDeadlineProbe'
$continued = Invoke-BoundedCheck $definition (Join-Path $root 'src') $directory -TimeoutSeconds 10 -AdditionalSources @($fixture)
Assert-Review ($continued.Status -eq 'Success' -and @(Get-ChildItem $directory -Filter '.worker-*').Count -eq 0) 'Next worker succeeds and scratch is cleaned'
# Exercise scheduling without filesystem replacement; real persistence remains in Milestone2.
. (Join-Path $root 'src\Orchestration.ps1')
. (Join-Path $root 'src\Events.ps1')
function Write-DiagnosticReport { param($Evidence,$OutputDirectory) }
$script:probeCount = 0
$executor = {
    param($Definition,$Timeout,$Directory)
    if ($Definition.FunctionName -eq 'Invoke-ConnectivityProbe') {
        Assert-Review ($Timeout -eq 12 -and $Definition.Arguments.TimeoutMs -eq 2000) 'Worker allows two-second probe plus ten-second overhead despite one-second passive budget'
        $script:probeCount++
    }
    [pscustomobject]@{ Name = $Definition.Name; Status = 'Success'; Data = @(); Error = $null }
}
$run = Invoke-SnapshotRun -RepositoryRoot $root -CheckTimeoutSeconds 1 -ProbeTimeoutSeconds 2 -ProbeWorkerOverheadSeconds 10 -IncludeConnectivityTests -CheckExecutor $executor
Assert-Review ($script:probeCount -eq 3 -and $run.Evidence.CollectionStatus -eq 'Complete') 'Resolution scheduling completes with explicit budgets and mocked probes'
Write-Host "PASS: $script:count review assertions; synthetic failures and loopback-only TCP."
