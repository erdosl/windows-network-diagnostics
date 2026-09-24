#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Capture')){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\tests\capture-import-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$path=Join-Path $work 'bad.pcapng';[IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
$result=Import-CaptureEvidence $path (Join-Path $work 'report')
if($result.DecoderStatus -ne 'PartialOrUnsupported'){throw 'Malformed decode not reported'}
if(-not (Test-Path (Join-Path $work 'report\capture.pcapng'))){throw 'Raw artifact lost'}
if($result.Artifact.Path -ne 'capture.pcapng' -or -not $result.Artifact.Sha256){throw 'Safe artifact reference/hash missing'}
Write-Host 'PASS: 3 offline import assertions; raw artifact retained on decode failure.'
