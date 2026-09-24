#requires -Version 5.1
param([string]$SourceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'src\Core.ps1')
. (Join-Path $SourceRoot 'src\State.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root ('output\tests\size-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$baseline=New-DhcpReviewFixture
$baseline | ConvertTo-Json -Depth 24 | Set-Content (Join-Path $dir 'baseline.json') -Encoding UTF8
$input=Read-ContextInput (Join-Path $dir 'baseline.json') Baseline SYNTHETIC
$current=New-DhcpReviewFixture -Current
$current.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($input)})
$paths=Write-DiagnosticReport $current (Join-Path $dir 'report')
[pscustomobject]@{JsonBytes=(Get-Item $paths.JsonPath).Length;HtmlBytes=(Get-Item $paths.HtmlPath).Length;Directory=$dir} | Format-List
