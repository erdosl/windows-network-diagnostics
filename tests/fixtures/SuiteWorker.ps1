function Invoke-TestSuiteFile {
    param([string]$Path)
    $ErrorActionPreference='Continue'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $output=@(& powershell.exe -NoProfile -NonInteractive -File $Path 2>&1 | ForEach-Object {$_ | Out-String})
    $code=$LASTEXITCODE;$watch.Stop()
    [pscustomobject]@{ExitCode=$code;DurationSeconds=$watch.Elapsed.TotalSeconds;Output=$output -join "`n";Runtime=$PSVersionTable.PSVersion.ToString();OS=[Environment]::OSVersion.Version.ToString()}
}
