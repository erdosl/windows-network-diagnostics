#requires -Version 5.1
Import-Module Microsoft.PowerShell.Utility
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
function Assert($v,$m){if(-not $v){throw $m}}
$script:count=0
function Get-WinEvent {param($ListLog,$FilterHashtable,$MaxEvents,$ErrorAction);if($ListLog){return [pscustomobject]@{IsEnabled=$true;ProviderNames=@('Present')}};for($i=0;$i -lt $script:count;$i++){[pscustomobject]@{TimeCreated=[datetime]'2026-01-01';Id=1;ProviderName='Present';RecordId=$i;Message='Synthetic';LevelDisplayName='Information'}}}
function Convert-NetworkEvent {param($Event);$Event}
$a=Get-RecentNetworkEvents System ([datetime]'2026-01-01') ([datetime]'2026-01-02') 2 @('Missing');Assert ($a.QueryStatus -eq 'Unavailable' -and $a.IntervalCoverage -eq 'Unavailable') 'Unavailable nested coverage'
$a=Get-RecentNetworkEvents System ([datetime]'2026-01-01') ([datetime]'2026-01-02') 2 @('Present','Missing');Assert ($a.IntervalCoverage -eq 'Partial') 'Partial providers'
$a=Get-RecentNetworkEvents System ([datetime]'2026-01-01') ([datetime]'2026-01-02') 2 @('Present');Assert ($a.IntervalCoverage -eq 'Complete' -and $a.ReturnedCount -eq 0) 'Valid zero-event coverage'
$a=Get-RecentNetworkEvents System ([datetime]'2026-01-01') ([datetime]'2026-01-02') 2 @();Assert ($a.AvailableProviders -contains 'Present' -and $a.RequestedProviders.Count -eq 0) 'Unfiltered log provider inventory lost'
$script:count=2;$a=Get-RecentNetworkEvents System ([datetime]'2026-01-01') ([datetime]'2026-01-02') 2 @('Present');Assert ($a.IntervalCoverage -eq 'Uncertain' -and $a.PossibleGap) 'Limit equality must indicate possible gap'
$check=[pscustomobject]@{Name='Events:System:Network';Status='Success';Data=@($a)}
Assert ((@(Get-EventCoverageSummary @($check)))[0].IntervalCoverage -eq 'Uncertain') 'Nested summary missing'
$script:files=@{};$script:time=0;$script:starts=@()
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='MODEL'}}
$execute={param($definition,$timeout,$directory)
    $script:time+=0.01;$data=@()
    if($definition.Name -eq 'Events:System:Network'){$script:starts+= $definition.Arguments.StartTime;$data=@($a)}
    [pscustomobject]@{Name=$definition.Name;Status='Success';Data=$data;Error=$null}
}
$run=Invoke-ObservationRun -RepositoryRoot $root -OutputRoot $work -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $execute -ElapsedClock {$script:time} -WaitAction {param($seconds);$script:time+=$seconds}
Assert ($script:starts.Count -eq 2 -and $script:starts[1] -ge $script:starts[0]) 'Cursor did not advance boundedly'
Assert ($run.Evidence.Samples[0].EventCoverage[0].PossibleGap) 'Capped interval gap lost on cursor advance'
$html=$script:files[(Join-Path $run.Directory 'summary.html')]
Assert ($html -notmatch 'publication in progress|"Rendering"' -and $html -match 'canonical evidence revision') 'Stale publication claim in HTML'
Assert ($run.Evidence.Publication.Html -eq 'Published') 'Canonical publication outcome lost'
Write-Host 'PASS: provider/query/interval coverage, zero events, cap gaps, cursor advancement and stable report metadata; modeled persistence.'
