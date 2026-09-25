#requires -Version 5.1
param([string]$RepositoryRoot,[string]$Work,[ValidateSet('Json','Html','Both','Success')][string]$Scenario,[switch]$Model)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $RepositoryRoot "src\$file.ps1")}
$script:realWriter=${function:Set-AtomicText};$script:files=@{};$script:entered=$false;$script:time=0;$script:calls=0
function Set-AtomicText {
    param($Path,$Text)
    if($Path.EndsWith('evidence.json')){
        $value=$Text | ConvertFrom-Json
        if($null -ne $value.Timing.CollectionElapsedSeconds -and $Scenario -in @('Json','Both')){$script:entered=$true;throw [IO.IOException]::new('Injected FINAL JSON failure')}
    }
    if($Path.EndsWith('summary.html') -and $Scenario -eq 'Html'){$script:entered=$true;throw [IO.IOException]::new('Injected HTML failure')}
    if($Model){$script:files[$Path]=$Text}else{& $script:realWriter $Path $Text}
}
if($Model){function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='MODELED'}}}
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.7.0';IsElevated=$false;StartedAt='2026-01-01T00:00:00Z'}}
$execute={param($definition,$timeout,$directory)
    $script:calls++;$script:time+=0.1
    if($Scenario -eq 'Both' -and $script:calls -eq 3){throw [InvalidOperationException]::new('Injected collection failure')}
    [pscustomobject]@{Name=$definition.Name;Status='Success';Data=@();Error=$null}
}
try {
    $run=Invoke-ObservationRun -RepositoryRoot $RepositoryRoot -OutputRoot $Work -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $execute -ElapsedClock {$script:time} -WaitAction {param($seconds);$script:time+=$seconds}
    if($Scenario -ne 'Success'){throw 'Expected fault not raised'}
} catch {
    $failure=$_;$directory=@(Get-ChildItem -LiteralPath $Work -Directory | Where-Object Name -like 'observation-*')[-1].FullName
    $path=Join-Path $directory 'evidence.json'
    $saved=$null
    if($Model){$saved=$script:files[$path] | ConvertFrom-Json}else{if([IO.File]::Exists($path)){$saved=Read-DiagnosticEvidence $path}}
    $result=[pscustomobject]@{FaultReached=$script:entered;ChecksAttempted=$script:calls;RecoverableSamples=@($saved.Samples).Count;SavedCollectionStatus=$saved.CollectionStatus;SavedPublication=$saved.Publication;Stage=$failure.Exception.Data['Stage'];HasCollectionError=($null -ne $failure.Exception.Data['CollectionError']);CollectionMessage=$failure.Exception.Data['CollectionError'].Exception.Message;HasInner=($null -ne $failure.Exception.InnerException);Message=$failure.Exception.Message}
    [IO.File]::WriteAllText((Join-Path $Work 'fault-result.json'),(ConvertTo-Json $result -Depth 8))
    throw
}
