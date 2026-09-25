#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
foreach($scenario in @('Json','Html','Both')){
    $dir=Join-Path $work ($scenario+' [literal] with spaces');$null=[IO.Directory]::CreateDirectory($dir)
    $ErrorActionPreference='Continue'
    $output=& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'fixtures\FinalizationFault.ps1') -RepositoryRoot $root -Work $dir -Scenario $scenario 2>&1
    $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
    $result=Get-Content -LiteralPath (Join-Path $dir 'fault-result.json') -Raw | ConvertFrom-Json
    if($result.HasCollectionError -and $result.CollectionMessage -ne 'Injected collection failure'){throw "Earlier real persistence blocked fault injection: $($result.CollectionMessage)"}
    if(-not $result.FaultReached){throw "Earlier real persistence blocked fault injection: $($result.Message)"}
    if($code -eq 0 -or $result.RecoverableSamples -lt 1 -or -not $result.HasInner){throw 'Finalization failure/recovery contract failed'}
    $run=@(Get-ChildItem -LiteralPath $dir -Directory)[0].FullName
    if(-not [IO.File]::Exists((Join-Path $run 'evidence.json.bak')) -or -not [IO.File]::Exists((Join-Path $run 'sample-0000.json'))){throw 'Recovery backup/sample lost'}
    if($scenario -eq 'Both' -and -not $result.HasCollectionError){throw 'Collection error lost'}
}
Write-Host 'PASS: real checkpoints, backups and samples survive three finalization faults; actual child commands exit nonzero.'
