#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\State.ps1');. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1')
foreach($entry in @('Verify-NetworkDiagnostics.ps1','tests\Run-Tests.ps1')){
    $entryPath=Join-Path $root $entry
    $null=& powershell.exe -NoProfile -File $entryPath '-?'
    if($LASTEXITCODE -ne 0){throw ('Help execution failed: '+$entry)}
    $helpText=Get-Help -Name $entryPath -Full | Out-String
    if($helpText -notmatch 'EXAMPLE'){throw ('Help examples missing: '+$entry)}
}
$work=New-TestWorkRoot;$copy=Join-Path $work 'checkout with spaces';$null=[IO.Directory]::CreateDirectory($copy)
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination (Join-Path $copy 'src') -Recurse
foreach($entry in @('Collect-NetworkDiagnostics.ps1','Watch-NetworkDiagnostics.ps1','Verify-NetworkDiagnostics.ps1')){Copy-Item -LiteralPath (Join-Path $root $entry) -Destination (Join-Path $copy $entry)}
# Replace only the orchestration function in the disposable copy. Actual entry
# parsing/dot-sourcing/parameter forwarding execute; no collector runs.
$stub=@'
function Invoke-SnapshotRun {
    param($RepositoryRoot,$OutputRoot)
    $id=[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString()}
    $dir=New-DiagnosticRunDirectory $RepositoryRoot $OutputRoot 'Snapshot' $id
    [IO.File]::WriteAllText((Join-Path $dir 'forwarded.txt'),$OutputRoot)
    [pscustomobject]@{JsonPath=(Join-Path $dir 'evidence.json');HtmlPath=(Join-Path $dir 'summary.html');Evidence=[pscustomobject]@{Checks=@()}}
}
'@
[IO.File]::AppendAllText((Join-Path $copy 'src\Orchestration.ps1'),"`r`n"+$stub)
$stub=$stub.Replace('Invoke-SnapshotRun','Invoke-ObservationRun').Replace("'Snapshot'","'Observation'")
[IO.File]::AppendAllText((Join-Path $copy 'src\Observation.ps1'),"`r`n"+$stub)
Push-Location $work
try{
    foreach($entry in @('Collect-NetworkDiagnostics.ps1','Watch-NetworkDiagnostics.ps1')){
        $null=& powershell.exe -NoProfile -File (Join-Path $copy $entry) '-?'
        if($LASTEXITCODE -ne 0){throw 'Entry help execution failed'}
        # Native -? may render on the host instead of redirected stdout. Check
        # the actual file's help object separately from its command exit code.
        $text=Get-Help -Name (Join-Path $copy $entry) -Full | Out-String
        if($text -notmatch 'OutputRoot' -or $text -notmatch 'EXAMPLE'){throw 'OutputRoot help/examples missing'}
        $null=& powershell.exe -NoProfile -File (Join-Path $copy $entry) -OutputRoot '.\reports [literal] with spaces'
        if($LASTEXITCODE -ne 0){throw 'Entry forwarding failed'}
    }
    $runs=@(Get-ChildItem -LiteralPath (Join-Path $work 'reports [literal] with spaces') -Directory)
    if($runs.Count -ne 2){throw 'Unique relative output directories not created in caller location'}
    foreach($dir in $runs){if([IO.File]::ReadAllText((Join-Path $dir.FullName '.gitignore')).Trim() -ne '*'){throw 'Custom run lacks generated-artifact Git exclusion'}}
    foreach($dir in $runs){if([IO.File]::ReadAllText((Join-Path $dir.FullName 'forwarded.txt')) -ne '.\reports [literal] with spaces'){throw 'OutputRoot forwarding altered'}}
    $id=[pscustomobject]@{ComputerName='SYNTHETIC';RunId='fixed-test-identity'}
    $null=New-DiagnosticRunDirectory $root '.\collision' Snapshot $id
    $blocked=$false;try{$null=New-DiagnosticRunDirectory $root '.\collision' Snapshot $id}catch{$blocked=$true}
    if(-not $blocked){throw 'Existing report directory reused'}
}finally{Pop-Location}
Write-Host 'PASS: real entry help, dot-sourcing, forwarding, literal output paths and collision refusal from another directory; orchestration mocked.'
