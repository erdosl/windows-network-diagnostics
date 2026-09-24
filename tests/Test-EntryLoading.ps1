#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root ('output\tests\entry path with spaces '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination (Join-Path $work 'src') -Recurse
foreach($entry in @('Collect-NetworkDiagnostics.ps1','Watch-NetworkDiagnostics.ps1','Capture-NetworkDiagnostics.ps1','Import-NetworkCapture.ps1')){Copy-Item -LiteralPath (Join-Path $root $entry) -Destination (Join-Path $work $entry)}
$count=0
Push-Location $env:TEMP
try{
    foreach($entry in @('Collect-NetworkDiagnostics.ps1','Watch-NetworkDiagnostics.ps1','Capture-NetworkDiagnostics.ps1','Import-NetworkCapture.ps1')){
        $null=& powershell.exe -NoProfile -File (Join-Path $work $entry) '-?'
        if($LASTEXITCODE -ne 0){throw "Entry help failed: $entry"};$count++
    }
    foreach($source in @('Core','State','Execution','Events','Collection','Connectivity','Orchestration','Observation','Capture')){. (Join-Path $work "src\$source.ps1")}
    foreach($command in @('Invoke-SnapshotRun','Invoke-ObservationRun','Invoke-CaptureRequest','Import-CaptureEvidence')){if(-not (Get-Command $command -ErrorAction SilentlyContinue)){throw "Missing $command"};$count++}
}finally{Pop-Location}
Write-Host "PASS: $count entry/help and dot-source assertions from another directory and a path with spaces. No collection/probes/capture executed."
