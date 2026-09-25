#requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module Microsoft.PowerShell.Utility
$root=Split-Path $PSScriptRoot -Parent
foreach($f in @('Core','State','Events','Collection','Observation')){. (Join-Path $root "src\$f.ps1")}
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$n=0
function Assert($ok,$why){if(-not $ok){throw $why};$script:n++}
function Pair($a,$b){Compare-ObservationDhcpState (Get-ObservationDhcpState $a.Checks) (Get-ObservationDhcpState $b.Checks) 'sample-before.json' 'sample-after.json'}
function Extra($f){
    foreach($i in @(91,92)){
        $r=$f.Checks[1].Data[0] | Select-Object *
        $r.SettingID='22222222-2222-2222-2222-'+$i.ToString('000000000000');$r.InterfaceIndex=$i
        $r | Add-Member NoteProperty IPEnabled $false
        $f.Checks[1].Data+= $r
    }
}
$a=New-DhcpReviewFixture;$b=New-DhcpReviewFixture;Extra $a;Extra $b
$c=Pair $a $b
Assert ($c.Coverage -eq 'Partial' -and $c.Outcome -eq 'Not assessed') 'Mixed source not wholly unchanged'
Assert (@($c.Adapters | Where-Object Outcome -eq 'Unchanged').Count -eq 12) 'Good adapters unchanged despite unrelated records'
Assert (@($c.Adapters | Where-Object Outcome -eq 'Not assessed').Count -eq 2) 'Both unmatched records retained'
Assert ($c.Reasons[0].Artifact -eq 'sample-before.json' -and $c.Reasons[1].Artifact -eq 'sample-after.json') 'Reasons artifact qualified'
$b.Checks[1].Data[0].DHCPServer='192.0.2.90'
Assert ((Pair $a $b).Outcome -eq 'Changed') 'Server despite unmatched'
$b.Checks[1].Data[0].DHCPServer=$a.Checks[1].Data[0].DHCPServer;$b.Checks[1].Data[0].DNSDomain='<other>.test'
Assert ((Pair $a $b).Outcome -eq 'Changed') 'Domain despite unmatched'
Assert ((ConvertTo-ObservationChangesHtml @((Pair $a $b))) -notmatch '<other>') 'HTML escapes changes'
$b.Checks[1].Data[0].DNSDomain=$a.Checks[1].Data[0].DNSDomain;$b.Checks[1].Data[0].DHCPLeaseExpires='2026-01-01T12:00:00Z'
Assert ((Pair $a $b).Outcome -eq 'Changed') 'Lease became available despite unmatched record'
$b=New-DhcpReviewFixture;$a=New-DhcpReviewFixture;$b.Checks[1].Data+=$b.Checks[1].Data[0]
$c=Pair $a $b
Assert (@($c.Adapters | Where-Object Outcome -eq 'Unchanged').Count -eq 11) 'Duplicate affects only implicated identity'
$b=New-DhcpReviewFixture;$b.Checks[0].Data[0].InterfaceGuid=$b.Checks[0].Data[1].InterfaceGuid
Assert (@((Pair $a $b).Adapters | Where-Object Outcome -eq 'Unchanged').Count -eq 10) 'Conflict local to implicated identities'
$b=New-DhcpReviewFixture;[array]::Reverse($b.Checks[1].Data)
Assert ((Pair $a $b).Outcome -eq 'Unchanged') 'Reordering'
$b=New-DhcpReviewFixture;$b.Checks[1].Data[0].InterfaceIndex=2
Assert ((Pair $a $b).Coverage -eq 'Partial') 'Index reuse not identity proof'
$b=New-DhcpReviewFixture;$b.Checks[1].Status='Failed'
Assert (@((Pair $a $b).Adapters | Where-Object Outcome -ne 'Not assessed').Count -eq 0) 'Missing source'
$b=New-DhcpReviewFixture;$b.Checks[1].Data=@($b.Checks[1].Data | Select-Object -Skip 1)
Assert ((Pair $a $b).Adapters[0].Outcome -eq 'Not assessed') 'Missing counterpart not removal'
Assert ((Pair $b $a).Adapters[0].Outcome -eq 'Not assessed') 'Appearing counterpart not continuity'

# Pure scheduling/persistence model: no provider calls or real atomic replacement.
$work=Join-Path $root ('output\tests\live-model-'+[guid]::NewGuid().ToString('N'))
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='MODEL-HASH'}}
function Get-EventDefinitions {param($a,$b,$c,$d,$e,$f);@()}
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();StartedAt=[DateTimeOffset]::Now.ToString('o')}}
function Run($clock,$executor){
    $script:files=@{};$script:calls=0
    Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -TestOutputRoot $work -ElapsedClock $clock -WaitAction {$script:time=10} -CheckExecutor $executor
}
$exec={param($d,$t,$w);$script:calls++;$script:time=10;[pscustomobject]@{Name=$d.Name;Status='TimedOut';Data=@();Error=$null}}
$r=Run {9.53} $exec
Assert ($r.Evidence.Samples.Count -eq 0 -and $script:calls -eq 0) 'Subminimum budget no artifact'
$script:ticks=0
$r=Run {$script:ticks++;if($script:ticks -eq 1){0}else{10}} $exec
Assert ($r.Evidence.Samples.Count -eq 0 -and $script:calls -eq 0) 'Deadline race no empty artifact'
$script:ticks=0
$r=Run {$script:ticks++;if($script:ticks -le 3){0}else{10}} $exec
Assert ($r.Evidence.Samples.Count -eq 0 -and $script:calls -eq 0) 'Persistence race does not retain never-attempted sample'
$script:time=0;$r=Run {$script:time} $exec
$s=$script:files[(Join-Path $r.Directory 'sample-0000.json')] | ConvertFrom-Json
Assert ($r.Evidence.Samples.Count -eq 1 -and $s.Checks[0].Status -eq 'TimedOut' -and $s.CollectionStatus -eq 'Incomplete') 'Attempted timeout retained'
Assert ($r.Evidence.Samples[0].Sha256 -eq 'MODEL-HASH') 'Retained sample hash recorded'
foreach($status in @('Failed','Success')){
    $script:time=0;$script:firstStatus=$status
    $r=Run {$script:time} {param($d,$t,$w);$script:calls++;$script:time=9.6;[pscustomobject]@{Name=$d.Name;Status=$script:firstStatus;Data=@();Error=$null}}
    Assert ($r.Evidence.Samples.Count -eq 1 -and $script:calls -eq 1) 'First attempted result retained without extra empty sample'
}

# One mocked provider enumeration, literal names, all adapter types retained.
$script:providerCalls=0
function Get-NetAdapterStatistics {param($Name,[switch]$IncludeHidden,$ErrorAction);$script:providerCalls++;Assert $IncludeHidden 'Includes hidden';$script:providerRows}
$ad=@([pscustomobject]@{Name='synthetic [a]*';InterfaceIndex=1;InterfaceGuid='11111111-1111-1111-1111-111111111111'},[pscustomobject]@{Name='synthetic missing';InterfaceIndex=2;InterfaceGuid='22222222-2222-2222-2222-222222222222'})
$script:providerRows=@([pscustomobject]@{Name=$ad[0].Name;InterfaceIndex=1;InterfaceGuid=$ad[0].InterfaceGuid;ReceivedBytes=10})
$batch=@(Invoke-ObservationStatistics $ad)
Assert ($script:providerCalls -eq 1 -and $batch[0].Status -eq 'Success' -and $batch[1].Status -eq 'Unavailable') 'Mixed batch statuses'
Assert ($batch[0].Data[0].StartedAt -and $batch[0].AdapterIdentity.InterfaceGuid) 'Counter timing and identity'
$script:providerRows+= $script:providerRows[0]
Assert (@(Invoke-ObservationStatistics $ad)[0].Status -eq 'Failed') 'Ambiguous provider mapping'
foreach($failure in @('Failed','TimedOut')){
    $script:time=0;$script:failure=$failure
    $r=Run {$script:time} {param($d,$t,$w)
        if($d.Name -eq 'ObservationStatistics'){$script:time=10;return [pscustomobject]@{Name=$d.Name;Status=$script:failure;Data=@();Error='Synthetic failure'}}
        [pscustomobject]@{Name=$d.Name;Status='Success';Data=$(if($d.Name -eq 'Adapters'){$ad}else{@()});Error=$null}
    }
    $s=$script:files[(Join-Path $r.Directory 'sample-0000.json')] | ConvertFrom-Json
    Assert (@($s.Checks | Where-Object { $_.Name -like 'AdapterStatistics:*' -and $_.Status -eq $script:failure}).Count -eq 2) 'Batch failure coverage per adapter'
}
Write-Host "PASS: $n live observation assertions; synthetic collectors and modeled persistence."
