function Invoke-TestCollector {
    param([string]$Mode, [string]$Value, [string]$MarkerRoot, [string]$ChildScript)
    if ($Mode -eq 'Echo') { return [pscustomobject]@{ Value = $Value; ProcessId = $PID; EnumValue = [Net.Sockets.AddressFamily]::InterNetwork } }
    if ($Mode -eq 'Fail') { throw 'Synthetic worker failure' }
    if ($Mode -eq 'SleepWithChild') {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $child = Start-Process -FilePath $exe -ArgumentList ('-NoProfile -NonInteractive -File "{0}" -MarkerPath "{1}"' -f $ChildScript, (Join-Path $MarkerRoot 'late-write.txt')) -WindowStyle Hidden -PassThru
        [IO.File]::WriteAllText((Join-Path $MarkerRoot 'child-pid.txt'), [string]$child.Id)
        Start-Sleep -Seconds 30
    }
}
