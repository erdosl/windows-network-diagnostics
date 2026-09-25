#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Execution')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'RunnerCore.ps1');. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
$fixtures=Join-Path $work 'suites';$null=[IO.Directory]::CreateDirectory($fixtures)
[IO.File]::WriteAllText((Join-Path $fixtures 'Test-Success.ps1'),"Write-Output 'success'; exit 0")
[IO.File]::WriteAllText((Join-Path $fixtures 'Test-Failure.ps1'),"Write-Output 'failure'; exit 7")
[IO.File]::WriteAllText((Join-Path $fixtures 'Test-Timeout.ps1'),"Write-Output 'before timeout'; Start-Sleep -Seconds 30")
$catalog=@{'Test-Success'='Synthetic';'Test-Failure'='Synthetic';'Test-Timeout'='Synthetic'}
Test-SuiteCatalog $fixtures $catalog
$dir=Join-Path $work 'complete';$null=[IO.Directory]::CreateDirectory($dir)
$r=Invoke-ValidationCatalog $root $fixtures @('Test-Success','Test-Failure','Test-Timeout') $catalog $dir 3 ([pscustomobject]@{Suites=@()})
if($r.Status -ne 'Complete' -or $r.Suites[0].ExitCode -ne 0 -or $r.Suites[1].ExitCode -ne 7 -or $null -ne $r.Suites[2].ExitCode -or $r.Suites[2].WorkerStatus -ne 'TimedOut'){throw 'Suite exit/status distinction failed'}
if([IO.File]::ReadAllText((Join-Path $dir 'Test-Timeout.log')) -notmatch 'before timeout'){throw 'Partial timeout output lost'}
if(Get-Process -Id $r.Suites[2].WorkerProcessId -ErrorAction SilentlyContinue){throw 'Timed-out worker still running'}
$dir=Join-Path $work 'interrupted';$null=[IO.Directory]::CreateDirectory($dir)
try{$null=Invoke-ValidationCatalog $root $fixtures @('Test-Success','Test-Failure') $catalog $dir 3 ([pscustomobject]@{Suites=@()}) -AfterSuite {throw 'Injected interruption'}}catch{if($_.Exception.Message -ne 'Injected interruption'){throw}}
$r=Get-Content -LiteralPath (Join-Path $dir 'results.json') -Raw | ConvertFrom-Json
if($r.Status -ne 'Incomplete' -or $r.Suites.Count -ne 1 -or $r.Suites[0].ExitCode -ne 0){throw 'Earlier suite lost on interruption'}
[IO.File]::WriteAllText((Join-Path $fixtures 'Test-Uncategorized.ps1'),'exit 0');$rejected=$false;try{Test-SuiteCatalog $fixtures $catalog}catch{$rejected=$true};if(-not $rejected){throw 'Uncategorized suite accepted'}
Write-Host 'PASS: disposable real suite workers, exit codes, timeout partial output and cleanup, immutable parent checkpoints and incomplete recovery.'
