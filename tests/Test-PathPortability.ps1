#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\State.ps1')
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1')
$work=New-TestWorkRoot
$count=0
# An actually absent short directory must not be diagnosed as a long path.
try{Set-AtomicText (Join-Path $work 'absent\evidence.json') 'x';throw 'Expected missing directory'}
catch{if($_.Exception.ToString() -notmatch 'DirectoryNotFoundException' -or $_.Exception.ToString() -match 'path budget|shorter checkout/output|runtime limits'){throw};$count++}
$long=Join-Path $work (('x'*256)+'.json')
try{Set-AtomicText $long 'x';throw 'Expected long path rejection'}
catch{if($_.Exception.ToString() -notmatch 'PathTooLongException' -or $_.Exception.Message -notmatch 'shorter checkout/output'){throw};$count++}
# Construct a supported directory where the old appended temporary name exceeds
# MAX_PATH but the new same-directory random basename fits.
$dir=Join-Path $work ('p'*(210-$work.Length-1))
$null=New-Item -ItemType Directory $dir
$path=Join-Path $dir 'evidence.json'
$oldTemporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
try{
    $s=[IO.File]::Open($oldTemporary,[IO.FileMode]::CreateNew);$s.Dispose()
    [IO.File]::Delete($oldTemporary)
    Write-Host 'INFO: This runtime accepts the old 261-character temporary path; Windows 11 failure not reproduced here.'
} catch{if($_.Exception.ToString() -notmatch 'PathTooLongException|DirectoryNotFoundException'){throw};Write-Host 'INFO: Legacy long temporary creation failed on this runtime.'}
$count++
Set-AtomicText $path 'first'
if([IO.File]::ReadAllText($path) -ne 'first'){throw 'First atomic publication failed'};$count++
Write-Host "PASS: $count path classification/legacy reproduction/first-write assertions before replacement."
Set-AtomicText $path 'second'
if([IO.File]::ReadAllText($path) -ne 'second' -or [IO.File]::ReadAllText($path+'.bak') -ne 'first'){throw 'Atomic replacement/backup failed'};$count++
if(@(Get-ChildItem -LiteralPath $dir -Filter '*.tmp').Count){throw 'Temporary file leaked'};$count++
Write-Host "PASS: $count path portability assertions, actual atomic writes and backup."
