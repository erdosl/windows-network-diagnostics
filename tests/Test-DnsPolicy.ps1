#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Execution','Connectivity','Orchestration')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
function Assert($v,$m){if(-not $v){throw $m}}
function Get-DnsClientNrptPolicy {param([switch]$Effective,$ErrorAction);if(-not $Effective){throw 'Effective required'};foreach($ns in @('.example.test','.internal.test')){[pscustomobject]@{Namespace=$ns;NameServers=@('192.0.2.53');DnsSecValidationRequired=$true;Secret='excluded'}}}
$r=Get-EffectiveDnsPolicy;Assert ($r.Policies.Count -eq 2 -and $r.Policies[0].Settings.PSObject.Properties.Name -notcontains 'Secret') 'Policy namespace/field selection'
function Get-DnsClientNrptPolicy {param([switch]$Effective,$ErrorAction)}
Assert ((Get-EffectiveDnsPolicy).PolicyState -eq 'ObservedEmpty') 'Successful empty policy not distinguished'
function Get-DnsClientNrptPolicy {param([switch]$Effective,$ErrorAction);throw [UnauthorizedAccessException]::new('localized denial')}
Assert ((Invoke-DiagnosticCheck Policy {Get-EffectiveDnsPolicy}).Status -eq 'PermissionDenied') 'Access failure misclassified'
function Get-DnsClientNrptPolicy {param([switch]$Effective,$ErrorAction);throw [Management.Automation.CommandNotFoundException]::new('missing')}
Assert ((Invoke-DiagnosticCheck Policy {Get-EffectiveDnsPolicy}).Status -eq 'Unavailable') 'Missing capability misclassified'
function Get-DnsClientGlobalSetting {param($ErrorAction);[pscustomobject]@{SuffixSearchList=@('example.test','internal.test');UseDevolution=$true;DevolutionLevel=2;Other='excluded'}}
$r=Get-GlobalDnsSettings;Assert ($r.Settings.SuffixSearchList.Count -eq 2 -and $r.Settings.DevolutionLevel -eq 2 -and -not $r.Settings.PSObject.Properties['Other']) 'Global field selection'
$mock=Join-Path $work 'slow-policy.ps1';[IO.File]::WriteAllText($mock,'function Get-DnsClientNrptPolicy { param([switch]$Effective,$ErrorAction); Start-Sleep -Seconds 20 }')
$r=Invoke-BoundedCheck ([pscustomobject]@{Name='DNS:EffectivePolicy';FunctionName='Get-EffectiveDnsPolicy';Arguments=@{}}) (Join-Path $root 'src') $work 1 -AdditionalSources @($mock)
Assert ($r.Status -eq 'TimedOut' -and $r.TimeoutScope -eq 'Worker') 'Policy timeout scope'
function Set-AtomicText {param($Path,$Text)}
$execute={param($definition,$timeout,$directory);[pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();Error=$null}}
$r=Invoke-SnapshotRun -RepositoryRoot $root -OutputRoot $work -CheckExecutor $execute
foreach($name in @('DNS:EffectivePolicy','DNS:GlobalSettings')){Assert ($name -in $r.Evidence.PlannedChecks -and @($r.Evidence.Checks|Where-Object Name -eq $name).Count -eq 1) "Missing scheduled check $name"}
Write-Host 'PASS: mock DNS policy/global settings, empty/populated/multiple namespaces, capability/access failure, bounded worker timeout and named scheduling.'
