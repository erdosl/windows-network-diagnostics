#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Execution')){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\tests\win11 worker '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$origin=[Diagnostics.Stopwatch]::GetTimestamp()
$context=[pscustomobject]@{OriginTicks=$origin;Frequency=[Diagnostics.Stopwatch]::Frequency;RunId='synthetic-run'}
$adapter=[pscustomobject]@{Name='Renamed synthetic';InterfaceIndex=1;InterfaceGuid='11111111-1111-1111-1111-111111111111';InterfaceDescription='Synthetic installation identity'}
$definition=[pscustomobject]@{Name='ObservationStatistics';FunctionName='Invoke-TestStatisticsBatch';Arguments=@{Adapters=@($adapter);TimingContext=$context}}
$r=Invoke-BoundedCheck $definition (Join-Path $root 'src') $work 15 -AdditionalSources @((Join-Path $PSScriptRoot 'fixtures\AdapterProviders.ps1'))
if($r.Status -ne 'Success' -or $r.Data[0].Status -ne 'Success'){throw 'Serialized provider batch failed'}
$timing=$r.Data[0].Data[0].CounterTiming
$end=([Diagnostics.Stopwatch]::GetTimestamp()-$origin)/[double][Diagnostics.Stopwatch]::Frequency
if($timing.RunId -ne 'synthetic-run' -or $timing.StartSeconds -lt 0 -or $timing.EndSeconds -gt $end -or $timing.EndSeconds -lt $timing.StartSeconds){throw 'Cross-process shared Stopwatch origin failed'}
if($r.Data[0].Data[0].ProviderDiagnostic.MatchBasis -ne 'InterfaceDescription'){throw 'Alternate identity lost during serialization'}
if(Get-Process -Id $r.WorkerProcessId -ErrorAction SilentlyContinue){throw 'Completed worker still alive'}
# Recovery exercises actual file reads independently of the File.Replace test suite.
$path=Join-Path $work 'recovery.json'
[IO.File]::WriteAllText($path,'invalid JSON',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText(($path+'.bak'),'{"SchemaVersion":9,"RunId":"synthetic-run","ComputerName":"SYNTHETIC","CollectionStatus":"Complete","CompletedAt":"2026-01-01T00:00:00Z"}',[Text.UTF8Encoding]::new($false))
$recovered=Read-DiagnosticEvidence $path
if($recovered.CollectionStatus -ne 'Incomplete' -or $null -ne $recovered.CompletedAt -or $recovered.RunId -ne 'synthetic-run'){throw 'Recovery changed identity or completeness'}
Write-Host 'PASS: 5 Windows 11 worker/recovery assertions; real Windows PowerShell worker and file reads, synthetic provider only.'
