#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1')
$work=New-TestWorkRoot
$checkout=Join-Path $work ('downloaded repository with spaces '+('p'*(170-$work.Length-34)))
$null=New-Item -ItemType Directory $checkout
foreach($folder in 'src','tests'){Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $checkout $folder) -Recurse}
$failed=$false
foreach($suite in 'Test-ObservationRun','Test-DhcpOrchestration'){
    & powershell.exe -NoProfile -File (Join-Path $checkout "tests\$suite.ps1")
    Write-Host "$suite from $($checkout.Length)-character checkout: exit $LASTEXITCODE"
    if($LASTEXITCODE -ne 0){$failed=$true}
}
if($failed){throw 'Long-checkout suites failed; inspect native errors above. No persistence tests skipped.'}
Write-Host 'PASS: Both real-persistence suites loaded from a long checkout with spaces.'
