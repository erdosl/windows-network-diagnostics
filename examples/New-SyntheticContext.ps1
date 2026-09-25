#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($name in @('Core','State')){. (Join-Path $root "src\$name.ps1")}
. (Join-Path $root 'tests\fixtures\DhcpReview.ps1')
$directory=Join-Path $root ('output\tests\synthetic-context-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($directory)
$baseline=New-DhcpReviewFixture;$baselinePath=Join-Path $directory 'baseline.json'
[IO.File]::WriteAllText($baselinePath,(ConvertTo-Json $baseline -Depth 24))
$expectations=[pscustomobject]@{Version=1;Defaults=[pscustomobject]@{AllowedDhcpServers=@('192.0.2.1');AllowedGateways=@('192.0.2.1')}}
$expectationsPath=Join-Path $directory 'expectations.json';[IO.File]::WriteAllText($expectationsPath,(ConvertTo-Json $expectations -Depth 5))
$current=New-DhcpReviewFixture -Current
$current.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@(Read-ContextInput $baselinePath Baseline SYNTHETIC)},[pscustomobject]@{Name='Expectations';Status='Success';Data=@(Read-ContextInput $expectationsPath Expectations SYNTHETIC)})
Update-DhcpContext $current
Write-Host "Synthetic baseline: $baselinePath"
Write-Host "Synthetic expectations: $expectationsPath"
$current.SnapshotComparison.Changes | Where-Object Outcome -ne Unchanged | Select-Object Field,Outcome,Before,After
