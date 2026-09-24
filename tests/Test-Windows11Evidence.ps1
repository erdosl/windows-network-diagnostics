#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Collection','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
$script:count=0
function Assert($ok,$why){if(-not $ok){throw $why};$script:count++}
$ad=@([pscustomobject]@{Name='Lab [1]* ?';InterfaceIndex=1;InterfaceGuid='11111111-1111-1111-1111-111111111111';InterfaceDescription='Synthetic NIC 1'},
    [pscustomobject]@{Name='Lab 2';InterfaceIndex=2;InterfaceGuid='22222222-2222-2222-2222-222222222222';InterfaceDescription='Synthetic NIC 2'})
$script:rows=@();$script:queryFailure=$false;$script:queries=0
function Get-NetAdapterStatistics {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    $script:queries++
    Assert ($IncludeHidden -and $Name -in @('*','Lab `[1`]`* `?')) 'Literal or single batch hidden query'
    if($script:queryFailure){throw [UnauthorizedAccessException]::new('Synthetic provider access failure')}
    $script:rows
}
function Detail {Invoke-DiagnosticCheck 'AdapterStatistics:1' {Invoke-AdapterDetail -Kind AdapterStatistics -AdapterName $ad[0].Name -InterfaceIndex 1 -InterfaceGuid $ad[0].InterfaceGuid -InterfaceDescription $ad[0].InterfaceDescription -AdapterInventory $ad}}
$r=Detail
Assert ($r.Status -eq 'Unavailable' -and $r.Error.ProviderDiagnostic.Outcome -eq 'ProviderRowsAbsent' -and -not $r.Error.ProviderDiagnostic.NativeException) 'Absent rows distinct from native error'
$script:rows=@([pscustomobject]@{InstanceID='opaque-provider-key';Name='Other';ReceivedBytes=4})
$r=Detail
Assert ($r.Error.ProviderDiagnostic.Outcome -eq 'PresentUnmatched' -and $r.Error.ProviderDiagnostic.Rows[0].InstanceID -eq 'opaque-provider-key') 'Unmatched rows and raw identity retained'
foreach($field in @('Name','InterfaceGuid','InterfaceDescription')){
    $script:rows=@([pscustomobject]@{ReceivedBytes=40;InstanceID='opaque'})
    $script:rows[0] | Add-Member NoteProperty $field $ad[0].$field
    $r=Detail
    Assert ($r.Status -eq 'Success' -and $r.Data[0].ProviderDiagnostic.MatchBasis -eq $field) "Exact supported shape $field"
}
$script:rows[0] | Add-Member NoteProperty Name 'Old alias'
Assert ((Detail).Status -eq 'Success') 'Renamed alias with exact installation identity'
$script:rows+=$script:rows[0]
Assert ((Detail).Error.ProviderDiagnostic.Outcome -eq 'Ambiguous') 'Duplicate provider rows not attributed'
$script:rows=@([pscustomobject]@{Name=$ad[0].Name;InterfaceGuid=$ad[1].InterfaceGuid;ReceivedBytes=40})
Assert ((Detail).Error.ProviderDiagnostic.Outcome -eq 'IdentityConflict') 'Conflicting GUID and alias retained'
$script:rows=@([pscustomobject]@{InterfaceDescription=$ad[0].InterfaceDescription;ReceivedBytes=40})
$ad[1].InterfaceDescription=$ad[0].InterfaceDescription
Assert ((Detail).Error.ProviderDiagnostic.Outcome -eq 'IdentityConflict') 'Duplicate inventory installation identity'
$ad[1].InterfaceDescription='Synthetic NIC 2'
$script:queries=0;$batch=@(Invoke-ObservationStatistics $ad)
Assert ($script:queries -eq 1 -and $batch[0].Status -eq 'Success' -and $batch[1].Status -eq 'Unavailable') 'One batch enumeration with mixed coverage'
$script:queryFailure=$true
$r=Invoke-DiagnosticCheck 'ObservationStatistics' {Invoke-ObservationStatistics $ad}
Assert ($r.Status -eq 'PermissionDenied' -and $r.Error.ProviderDiagnostic.QueryScope -eq 'BatchEnumeration' -and $r.Error.ProviderDiagnostic.AffectedAdapters.Count -eq 2) 'Global query failure preserves affected source coverage'
Assert ((Detail).Error.ProviderDiagnostic.Outcome -eq 'QueryFailed') 'Scoped query failure distinct from missing'
$script:powerMode='isolated'
function Get-NetAdapterPowerManagement {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    Assert ($Name -ne '*' -and $IncludeHidden) 'Power never enumerates whole provider'
    if($script:powerMode -eq 'global' -or $Name -eq 'Lab 2'){
        $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([ComponentModel.Win32Exception]::new(31),'Windows System Error 31',[Management.Automation.ErrorCategory]::NotSpecified,$Name))
    }
    Assert ($Name -eq 'Lab `[1`]`* `?') 'Literal wildcard power name escaped'
    [pscustomobject]@{Name=$ad[0].Name;WakeOnMagicPacket='Unsupported'}
}
function Power($a){Invoke-DiagnosticCheck 'AdapterPowerManagement' {Invoke-AdapterDetail -Kind AdapterPowerManagement -AdapterName $a.Name -InterfaceIndex $a.InterfaceIndex -InterfaceGuid $a.InterfaceGuid}}
Assert ((Power $ad[0]).Status -eq 'Success') 'Successful power adapter alongside isolated failure'
$r=Power $ad[1]
Assert ($r.Status -eq 'Failed' -and $r.Error.NativeErrorCode -eq 31 -and $r.Error.Id -match 'Windows System Error 31' -and $r.Error.ProviderDiagnostic.QueryScope -eq 'LiteralAdapterName') 'Error 31 remains original scoped provider failure'
$script:powerMode='global'
Assert ((Power $ad[0]).Status -eq 'Failed' -and (Power $ad[1]).Status -eq 'Failed') 'Globally failing provider not relabelled unsupported or hardware diagnosis'

$script:serviceState='Stopped';$script:inventoryMode='ethernet';$script:exitCode=1
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$Filter)
    if($script:serviceState -eq 'absent'){return}
    if($script:serviceState -eq 'denied'){throw [UnauthorizedAccessException]::new('Synthetic denied')}
    [pscustomobject]@{Name='wlansvc';State=$script:serviceState;Started=($script:serviceState -eq 'Running')}
}
function Get-NetAdapter {
    [CmdletBinding()]param([switch]$IncludeHidden)
    if($script:inventoryMode -eq 'failed'){throw 'Synthetic inventory failure'}
    [pscustomobject]@{Name='Synthetic';InterfaceType=$(if($script:inventoryMode -eq 'wifi'){71}elseif($script:inventoryMode -eq 'unknown'){$null}elseif($script:inventoryMode -eq 'unknown-enum'){99999}else{6})}
}
function Invoke-WlanCommand {[pscustomobject]@{Command='netsh wlan show interfaces';ExitCode=$script:exitCode;Text='Synthetic localized raw response <raw>'}}
function Wifi {Invoke-DiagnosticCheck 'WiFiConnection' {Get-WifiConnectionEvidence}}
$r=Wifi
Assert ($r.Status -eq 'Unavailable' -and $r.Error.Evidence.Reason -eq 'WlanServiceStopped' -and $r.Error.Evidence.Command.Text -match '<raw>') 'Stopped service with raw command retained'
$script:serviceState='absent'
Assert ((Wifi).Error.Evidence.Reason -eq 'WlanServiceAbsent') 'Absent service'
$script:serviceState='Running';$script:exitCode=0
Assert ((Wifi).Error.Evidence.Reason -eq 'NoWifiAdapterInCompleteInventory') 'Complete Ethernet-only inventory'
$script:inventoryMode='failed';$script:exitCode=1
Assert ((Wifi).Status -eq 'Failed' -and $null -eq (Wifi).Error.Evidence.Reason) 'Failed inventory is not no Wi-Fi'
$script:inventoryMode='unknown'
Assert ((Wifi).Status -eq 'Failed') 'Unknown interface capability is not no Wi-Fi'
$script:inventoryMode='unknown-enum'
Assert ((Wifi).Status -eq 'Failed') 'Unrecognized interface enum is not proof of no Wi-Fi'
$script:serviceState='denied';$script:exitCode=5
Assert ((Wifi).Status -eq 'PermissionDenied') 'Access denial distinct'
$script:serviceState='Stopped';$script:exitCode=99
Assert ((Wifi).Status -eq 'Failed') 'Unexpected command failure survives availability context'
$script:serviceState='Running';$script:inventoryMode='wifi';$script:exitCode=0
Assert ((Wifi).Status -eq 'Success') 'Successful WLAN response'

# Controllable clocks and modeled persistence isolate timing from filesystem restrictions.
$work=Join-Path $root ('output\tests\win11-clock-'+[guid]::NewGuid().ToString('N'))
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();StartedAt='2026-01-01T00:00:00Z'}}
function Get-EventDefinitions {param($a,$b,$c,$d,$e,$f);@()}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='SYNTHETIC'}}
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text;if($Path -like '*summary.html'){$script:time+=3}}
foreach($jump in @(-3600,3600)){
    $script:time=0;$script:files=@{};$script:wallJump=$jump
    $r=Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -TestOutputRoot $work -ElapsedClock {$script:time} -WallClock {([DateTimeOffset]'2026-01-01T00:00:00Z').AddSeconds($script:time+$(if($script:time -gt 0){$script:wallJump}else{0}))} -WaitAction {param($seconds);$script:time+=$seconds} -CheckExecutor {
        param($d,$timeout,$directory)
        $script:time+=0.1
        [pscustomobject]@{Name=$d.Name;Status='Success';Data=@();Error=$null}
    }
    Assert ($r.Evidence.Timing.CollectionElapsedSeconds -eq 10 -and $r.Evidence.Timing.TerminationReason -eq 'DeadlineBudgetExhausted') 'Monotonic deadline ignores wall jump'
    Assert ($r.Evidence.Timing.FinalizationElapsedSeconds -eq 3 -and $r.Evidence.Timing.WallMinusMonotonicSeconds -eq $jump) 'Finalization distinct and wall discrepancy measured'
    Assert ($r.Evidence.Samples.Count -eq 2 -and $r.Evidence.Samples[1].ActualIntervalSeconds -eq 5) 'Monotonic sample interval'
    Assert ($script:files[(Join-Path $r.Directory 'summary.html')] -match 'DeadlineBudgetExhausted') 'HTML timing visible'
}
$script:time=0;$script:files=@{}
$r=Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -TestOutputRoot $work -ElapsedClock {$script:time} -CheckExecutor {param($d,$timeout,$dir);$script:time+=11;[pscustomobject]@{Name=$d.Name;Status='TimedOut';Data=@();Error=$null}}
$s=$script:files[(Join-Path $r.Directory 'sample-0000.json')] | ConvertFrom-Json
Assert ($s.Checks.Count -eq 1 -and $s.CollectionStatus -eq 'Incomplete' -and $r.Evidence.Timing.CollectionElapsedSeconds -eq 11) 'Slow collector retains useful partial sample and measured overrun'
$script:time=0;$script:files=@{};$script:queryFailure=$false
$script:rows=@([pscustomobject]@{InterfaceDescription=$ad[0].InterfaceDescription;ReceivedBytes=40})
$r=Invoke-ObservationRun -RepositoryRoot $root -DurationSeconds 10 -IntervalSeconds 5 -TestOutputRoot $work -ElapsedClock {$script:time} -CheckExecutor {
    param($d,$timeout,$dir)
    if($d.Name -eq 'ObservationStatistics'){
        $script:time=10
        return Invoke-DiagnosticCheck $d.Name {Invoke-ObservationStatistics -Adapters $ad}
    }
    [pscustomobject]@{Name=$d.Name;Status='Success';Data=$(if($d.Name -eq 'Adapters'){$ad}else{@()});Error=$null}
}
$s=$script:files[(Join-Path $r.Directory 'sample-0000.json')] | ConvertFrom-Json
Assert ($s.StatisticsCoverage.BatchExecutionStatus -eq 'Success' -and $s.StatisticsCoverage.Status -eq 'Partial' -and $s.StatisticsCoverage.UsableAdapters -eq 1) 'Batch success separate from actual usable counter coverage'
Assert ($s.Checks[-1].EvidencePath -like '/Checks/*' -and $s.Checks[-1].Status -eq 'Unavailable') 'Per-adapter batch provenance survives serialization'
Assert ($script:files[(Join-Path $r.Directory 'summary.html')] -match 'UsableAdapters') 'HTML exposes statistics coverage'

$guid=$ad[0].InterfaceGuid
function CounterSample($start,$wall,$bytes){[pscustomobject]@{RunId='synthetic-run';Checks=@([pscustomobject]@{Name='Adapters';Status='Success';Data=@([pscustomobject]@{InterfaceGuid=$guid;Status='Up'})},[pscustomobject]@{Name='AdapterStatistics:1';Status='Success';Data=@([pscustomobject]@{InterfaceGuid=$guid;StartedAt=$wall;Fields=[pscustomobject]@{ReceivedBytes=$bytes};CounterTiming=[pscustomobject]@{RunId='synthetic-run';Basis='SystemStopwatch';StartSeconds=$start;EndSeconds=$start+0.2}})})}}
$a=CounterSample 1 '2026-01-01T01:00:00Z' 10;$b=CounterSample 6 '2026-01-01T00:00:00Z' 30
$d=@(Get-CounterDeltas $a $b 5)[0]
Assert ($d.PerSecond -eq 4 -and $d.ElapsedSeconds -eq 5 -and $d.IntervalBasis -match 'Stopwatch') 'Counter rate uses same-run shared clock despite backwards wall time'
$b.Checks[1].Data[0].CounterTiming.RunId='different-run'
Assert ($null -eq @(Get-CounterDeltas $a $b 5)[0].PerSecond) 'Never subtract unrelated counter origins'
$b.Checks[1].Data[0].CounterTiming=$null
Assert ($null -eq @(Get-CounterDeltas $a $b 5)[0].PerSecond -and @(Get-CounterDeltas $a $b 5)[0].Status -eq 'Not assessed') 'Legacy wall-only counter interval unassessed'
Write-Host "PASS: $script:count Windows 11 regression assertions; anonymized synthetic providers, clocks and modeled persistence."
