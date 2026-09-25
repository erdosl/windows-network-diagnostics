function Invoke-TestSuiteFile {
    param([string]$Path,[string]$PartialOutputPath)
    $ErrorActionPreference='Continue'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $text=[Text.StringBuilder]::new()
    & powershell.exe -NoProfile -NonInteractive -File $Path 2>&1 | ForEach-Object {
        $line=$_ | Out-String
        $remaining=65536-$text.Length
        if($remaining -gt 0){$part=$line.Substring(0,[Math]::Min($remaining,$line.Length));$null=$text.Append($part)
            # Bounded IPC scratch, never a report. Parent publishes the log.
            if($PartialOutputPath){[IO.File]::AppendAllText($PartialOutputPath,$part)}
        }
    }
    $code=$LASTEXITCODE;$watch.Stop()
    [pscustomobject]@{ExitCode=$code;DurationSeconds=$watch.Elapsed.TotalSeconds;Output=$text.ToString();OutputLimitCharacters=65536;Runtime=$PSVersionTable.PSVersion.ToString();OS=[Environment]::OSVersion.Version.ToString()}
}
