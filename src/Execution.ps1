function Invoke-BoundedCheck {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$WorkingDirectory, [ValidateRange(1,600)][int]$TimeoutSeconds = 30,
        [string[]]$AdditionalSources = @(),[switch]$CapturePartialOutput)
    $start = [DateTimeOffset]::Now
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $worker = $null
    $scratchRoot=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'output\tests\network-diagnostics-workers'))
    $scratch = Join-Path $scratchRoot ([guid]::NewGuid().ToString('N'))
    $result = $null
    $workerId = $null
    $partialOutput=$null
    try {
        if (-not ('NetworkDiagnostics.WorkerProcess' -as [type])) {
            Add-Type -Path (Join-Path $SourceDirectory 'NativeProcess.cs') -ErrorAction Stop
        }
        $null = [IO.Directory]::CreateDirectory($scratch)
        $inputFile = Join-Path $scratch 'request.clixml'
        $resultFile = Join-Path $scratch 'result.json'
        if($CapturePartialOutput){$Definition.Arguments.PartialOutputPath=Join-Path $scratch 'partial-output.txt'}
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
        if($CapturePartialOutput -and [IO.File]::Exists((Join-Path $scratch 'partial-output.txt'))){
            try{$reader=[IO.StreamReader]::new((Join-Path $scratch 'partial-output.txt'));try{$buffer=New-Object char[] 65536;$n=$reader.ReadBlock($buffer,0,$buffer.Length);$partialOutput=[string]::new($buffer,0,$n)}finally{$reader.Dispose()}}catch{$partialOutput='Partial output unavailable: '+$_.Exception.Message}
        }
        # The entire worker tree has been terminated before its private scratch is removed.
        if ([IO.Path]::GetFullPath($scratch).StartsWith($scratchRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        $watch.Stop()
    }
    [pscustomobject]@{ Name = $Definition.Name; StartedAt = $start.ToString('o'); CompletedAt = [DateTimeOffset]::Now.ToString('o')
        DurationMs = $watch.ElapsedMilliseconds; DurationBasis='Parent check Stopwatch including startup and cleanup'; TimeoutSeconds = $TimeoutSeconds; WorkerProcessId = $workerId
        Request = $Definition.Arguments; Status = $result.Status; PartialOutput=$partialOutput; TimeoutScope = $(if ($result.Status -eq 'TimedOut') { 'Worker' } else { $null }); Data = @($result.Data); Error = $result.Error }
}
