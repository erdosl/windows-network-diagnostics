param([Parameter(Mandatory)][string]$MarkerPath)
Start-Sleep -Seconds 8
[IO.File]::WriteAllText($MarkerPath, 'A timeout failed to stop this child.')
