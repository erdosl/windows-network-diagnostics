function Invoke-BoundedCheck {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$WorkingDirectory, [ValidateRange(1,600)][int]$TimeoutSeconds = 30,
        [string[]]$AdditionalSources = @())
    $start = [DateTimeOffset]::Now
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $worker = $null
    $scratch = Join-Path $WorkingDirectory ('.worker-' + [guid]::NewGuid().ToString('N'))
    $result = $null
    $workerId = $null
    try {
        if (-not ('NetworkDiagnostics.WorkerProcess' -as [type])) {
            Add-Type -Path (Join-Path $SourceDirectory 'NativeProcess.cs') -ErrorAction Stop
        }
        $null = New-Item -ItemType Directory -Path $scratch -ErrorAction Stop
        $inputFile = Join-Path $scratch 'request.clixml'
        $resultFile = Join-Path $scratch 'result.json'
        $sources = @('Core.ps1', 'Events.ps1', 'Collection.ps1', 'Connectivity.ps1') | ForEach-Object { Join-Path $SourceDirectory $_ }
        [pscustomobject]@{ Name = $Definition.Name; FunctionName = $Definition.FunctionName;
            Arguments = $Definition.Arguments; SourcePaths = @($sources) + @($AdditionalSources)
        } | Export-Clixml -LiteralPath $inputFile -Depth 24
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $workerScript = Join-Path $SourceDirectory 'Worker.ps1'
        $arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -InputPath "{1}" -ResultPath "{2}"' -f $workerScript, $inputFile, $resultFile
        $worker = New-Object NetworkDiagnostics.WorkerProcess($exe, $arguments, $SourceDirectory)
        $workerId = $worker.Id
        $remaining = [Math]::Max(0, ($TimeoutSeconds * 1000) - [int]$watch.ElapsedMilliseconds)
        if (-not $worker.Wait($remaining)) {
            $result = [pscustomobject]@{ Status = 'TimedOut'; Data = @(); Error = [pscustomobject]@{
                Message = "Check exceeded $TimeoutSeconds seconds; worker and descendants terminated."; Id = 'CheckTimeout'; Category = 'OperationTimeout'
            } }
        } elseif (Test-Path -LiteralPath $resultFile) {
            $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } else {
            throw 'Worker exited without a result. Script execution policy or worker startup may have blocked execution; no policy override was used.'
        }
    } catch {
        $failure = $_
        $result = Invoke-DiagnosticCheck -Name $Definition.Name -Action { throw $failure }
    } finally {
        if ($null -ne $worker) { $worker.Dispose() }
        # The entire worker tree has been terminated before its private scratch is removed.
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        $watch.Stop()
    }
    [pscustomobject]@{ Name = $Definition.Name; StartedAt = $start.ToString('o'); CompletedAt = [DateTimeOffset]::Now.ToString('o')
        DurationMs = $watch.ElapsedMilliseconds; TimeoutSeconds = $TimeoutSeconds; WorkerProcessId = $workerId
        Request = $Definition.Arguments; Status = $result.Status; Data = @($result.Data); Error = $result.Error }
}
