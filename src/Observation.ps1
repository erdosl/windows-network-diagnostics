function Get-ObservationState {
    param($Checks)
    $result=[ordered]@{}
    $fields=@{
        Adapters=@('InterfaceGuid','InterfaceIndex','Status','MacAddress')
        IPAddresses=@('InterfaceIndex','IPAddress','PrefixLength','AddressState','PrefixOrigin','SuffixOrigin')
        DHCPAndGateways=@('InterfaceIndex','SettingID','DHCPEnabled','DefaultIPGateway','DNSServerSearchOrder')
        Routes=@('InterfaceIndex','DestinationPrefix','NextHop','RouteMetric','InterfaceMetric','Protocol')
        DNSServers=@('InterfaceIndex','AddressFamily','ServerAddresses')
        InterfacesAndMetrics=@('InterfaceIndex','AddressFamily','ConnectionState','InterfaceMetric')
    }
    foreach($name in @($fields.Keys | Sort-Object)){
        $check=@($Checks | Where-Object Name -eq $name)
        if($check.Count -ne 1 -or $check[0].Status -ne 'Success' -or $check[0].Data -isnot [array]){$result[$name]=[pscustomobject]@{Status='Not assessed';Value=$null};continue}
        $values=@($check[0].Data | Select-Object -Property $fields[$name] | ForEach-Object {ConvertTo-Json $_ -Depth 8 -Compress} | Sort-Object)
        $result[$name]=[pscustomobject]@{Status='Success';Value=$values}
    }
    [pscustomobject]$result
}

function Compare-ObservationState {
    param($Before,$After)
    foreach($property in $After.PSObject.Properties){
        $name=$property.Name;$left=$Before.$name;$right=$property.Value
        $outcome='Not assessed'
        if($left.Status -eq 'Success' -and $right.Status -eq 'Success'){
            $outcome='Changed'
            if((ConvertTo-Json -InputObject $left.Value -Compress) -ceq (ConvertTo-Json -InputObject $right.Value -Compress)){$outcome='Unchanged'}
        }
        [pscustomobject]@{Source=$name;Outcome=$outcome;BeforeStatus=$left.Status;AfterStatus=$right.Status}
    }
}

function Select-NewObservationEvents {
    param($Group,[hashtable]$Seen)
    foreach($event in $Group.Events){
        $key=$Group.LogName+'|'+$event.RecordId+'|'+$event.TimeCreated
        if(-not $Seen.ContainsKey($key)){$Seen[$key]=$true;$event}
    }
}

function Get-CounterDeltas {
    param($Before,$After,[double]$ElapsedSeconds)
    $names=@('ReceivedBytes','SentBytes','ReceivedUnicastPackets','SentUnicastPackets','ReceivedPacketErrors','OutboundPacketErrors','ReceivedDiscardedPackets','OutboundDiscardedPackets')
    foreach($check in @($After.Checks | Where-Object Name -like 'AdapterStatistics:*')){
        $rows=@($check.Data);$row=$null;if($rows.Count -eq 1){$row=$rows[0]}
        $old=@($Before.Checks | Where-Object { $_.Name -like 'AdapterStatistics:*' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data} | Where-Object {$row.InterfaceGuid -and $_.InterfaceGuid -eq $row.InterfaceGuid})
        $discontinuity=$check.Status -ne 'Success' -or $old.Count -ne 1 -or -not $row.InterfaceGuid -or $ElapsedSeconds -le 0
        $counterSeconds=$ElapsedSeconds;$intervalBasis='Sample start times; counter timestamps unavailable'
        if($old.Count -eq 1 -and $old[0].StartedAt -and $row.StartedAt){
            $counterSeconds=([DateTimeOffset]::Parse($row.StartedAt)-[DateTimeOffset]::Parse($old[0].StartedAt)).TotalSeconds
            $intervalBasis='Counter collection start timestamps'
            if($counterSeconds -le 0){$discontinuity=$true}
        }
        $links=@($Before.Checks+$After.Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data} | Where-Object InterfaceGuid -eq $row.InterfaceGuid)
        if($links.Count -ne 2 -or $links[0].Status -ne $links[1].Status){$discontinuity=$true}
        foreach($name in $names){
            $a=$null;$b=$null;if($old.Count -eq 1){$a=$old[0].Fields.$name};if($row){$b=$row.Fields.$name}
            $delta=$null;$rate=$null;$status='Unavailable'
            if($null -ne $a -and $null -ne $b){
                $status='Discontinuity'
                if(-not $discontinuity -and [decimal]$b -ge [decimal]$a){$status='Delta';$delta=[decimal]$b-[decimal]$a;$rate=[double]$delta/$counterSeconds}
            }
            [pscustomobject]@{InterfaceGuid=$row.InterfaceGuid;Counter=$name;Before=$a;After=$b;ElapsedSeconds=$counterSeconds;IntervalBasis=$intervalBasis;Status=$status;Delta=$delta;PerSecond=$rate;Limitation='Sampled counters; an unseen reset may be undetectable. Errors/discards do not prove a physical fault.'}
        }
    }
}

function Invoke-ObservationRun {
    param([string]$RepositoryRoot,[ValidateRange(10,600)][int]$DurationSeconds=60,
        [ValidateRange(5,120)][int]$IntervalSeconds=10,[ValidateRange(1,60)][int]$CheckTimeoutSeconds=10,
        [string]$IncidentContextPath,[scriptblock]$CheckExecutor,[scriptblock]$CancelRequested,
        [string]$TestOutputRoot)
    $identity=New-SnapshotIdentity
    $outputRoot=Join-Path $RepositoryRoot 'output';if($TestOutputRoot){$outputRoot=$TestOutputRoot}
    $directory=Join-Path $outputRoot ('observation-'+($identity.ComputerName -replace '[^A-Za-z0-9_.-]','_')+'-'+$identity.RunId)
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $manifest=[pscustomobject]@{SchemaVersion=9;Mode='Observation';Identity=$identity;CollectionStatus='Incomplete';CompletedAt=$null
        DurationSeconds=$DurationSeconds;IntervalSeconds=$IntervalSeconds;Samples=@();IncidentContext=$null;Error=$null
        Limitation='Sequential samples, no overlap or queue. Transitions between samples can be missed. A failed sample is not unchanged state. No current-path fault is inferred.'}
    $save={Set-AtomicText (Join-Path $directory 'evidence.json') (ConvertTo-Json -InputObject $manifest -Depth 16)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$previous=$null;$eventEnds=@{};$seen=@{};$sequence=0
    try{
        & $save
        if($IncidentContextPath){
            try{$manifest.IncidentContext=Invoke-BoundedCheck ([pscustomobject]@{Name='IncidentContext';FunctionName='Read-IncidentContext';Arguments=@{Path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IncidentContextPath)}}) (Join-Path $RepositoryRoot 'src') $directory ([Math]::Min($DurationSeconds,$CheckTimeoutSeconds))}
            catch{$failure=$_;$manifest.IncidentContext=Invoke-DiagnosticCheck 'IncidentContext' {throw $failure}}
            & $save
        }
        while($watch.Elapsed.TotalSeconds -lt $DurationSeconds){
            if($CancelRequested -and (& $CancelRequested)){ $manifest.CollectionStatus='Interrupted';break }
            $sampleStart=[DateTimeOffset]::Now;$sampleClock=$watch.Elapsed.TotalSeconds
            $sample=[pscustomobject]@{SchemaVersion=9;RunId=$identity.RunId;Sequence=$sequence;StartedAt=$sampleStart.ToString('o');CompletedAt=$null;CollectionStatus='Incomplete';Checks=@();Changes=@();CounterDeltas=@();ActualIntervalSeconds=$null}
            if($previous){$sample.ActualIntervalSeconds=($sampleStart-[DateTimeOffset]::Parse($previous.StartedAt)).TotalSeconds}
            $relative='sample-{0:D4}.json' -f $sequence
            $samplePath=Join-Path $directory $relative
            Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
            $manifest.Samples+= [pscustomobject]@{Path=$relative;Sequence=$sequence;StartedAt=$sample.StartedAt;Status='Incomplete';Changes=@();CounterDiscontinuities=0;Sha256=$null}
            & $save
            $execute={param($definition)
                $remaining=[int][Math]::Floor($DurationSeconds-$watch.Elapsed.TotalSeconds)
                if($remaining -lt 1){return $false}
                $timeout=[Math]::Min($CheckTimeoutSeconds,$remaining)
                if($CheckExecutor){$check=& $CheckExecutor $definition $timeout $directory}
                else{$check=Invoke-BoundedCheck $definition (Join-Path $RepositoryRoot 'src') $directory $timeout}
                $sample.Checks+= $check
                Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
                $true
            }
            $complete=$true
            foreach($name in @('Adapters','IPAddresses','DHCPAndGateways','DNSServers','InterfacesAndMetrics','Routes','NICServices','Neighbours')){
                if(-not (& $execute ([pscustomobject]@{Name=$name;FunctionName='Invoke-SnapshotCollector';Arguments=@{Name=$name}}))){$complete=$false;break}
            }
            foreach($adapter in @($sample.Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data})){
                if(-not (& $execute ([pscustomobject]@{Name=('AdapterStatistics:'+$adapter.InterfaceIndex);FunctionName='Invoke-AdapterDetail';Arguments=@{Kind='AdapterStatistics';AdapterName=$adapter.Name;InterfaceIndex=$adapter.InterfaceIndex;InterfaceGuid=$adapter.InterfaceGuid}}))){$complete=$false;break}
            }
            $services=@($sample.Checks | Where-Object Name -eq 'NICServices' | ForEach-Object {$_.Data} | ForEach-Object {$_.ServiceName})
            foreach($definition in @(Get-EventDefinitions $sampleStart.LocalDateTime ([DateTimeOffset]::Now.LocalDateTime) 100 100 50 $services)){
                $from=[DateTimeOffset]::Parse($identity.StartedAt)
                if($eventEnds.ContainsKey($definition.Name)){$from=$eventEnds[$definition.Name]}
                $definition.Arguments.StartTime=$from.LocalDateTime
                $eventEnd=[DateTimeOffset]::Now;$definition.Arguments.EndTime=$eventEnd.LocalDateTime
                if(-not (& $execute $definition)){$complete=$false;break}
                $check=$sample.Checks[-1]
                if($check.Status -eq 'Success'){
                    $eventEnds[$definition.Name]=$eventEnd
                    foreach($group in $check.Data){
                        $group.Events=@(Select-NewObservationEvents $group $seen)
                    }
                }
            }
            $state=Get-ObservationState $sample.Checks
            if($previous){
                $sample.Changes=@(Compare-ObservationState (Get-ObservationState $previous.Checks) $state);$sample.CounterDeltas=@(Get-CounterDeltas $previous $sample $sample.ActualIntervalSeconds)
                foreach($change in $sample.Changes){
                    $change | Add-Member NoteProperty BeforeEvidence ([pscustomobject]@{Scope='Observation';RunId=$identity.RunId;Artifact=('sample-{0:D4}.json' -f ($sequence-1));SourceCheck=$change.Source})
                    $change | Add-Member NoteProperty AfterEvidence ([pscustomobject]@{Scope='Observation';RunId=$identity.RunId;Artifact=$relative;SourceCheck=$change.Source})
                }
            }
            if($complete){$sample.CollectionStatus='Complete'}
            $sample.CompletedAt=[DateTimeOffset]::Now.ToString('o')
            Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
            $manifest.Samples[-1].Status=$sample.CollectionStatus
            $manifest.Samples[-1].Changes=@($sample.Changes | Select-Object Source,Outcome)
            $manifest.Samples[-1].CounterDiscontinuities=@($sample.CounterDeltas | Where-Object Status -eq 'Discontinuity').Count
            $manifest.Samples[-1].Sha256=(Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash
            & $save
            $previous=$sample;$sequence++
            $remainingWait=[Math]::Min($IntervalSeconds-($watch.Elapsed.TotalSeconds-$sampleClock),$DurationSeconds-$watch.Elapsed.TotalSeconds)
            while($remainingWait -gt 0){
                if($CancelRequested -and (& $CancelRequested)){$manifest.CollectionStatus='Interrupted';break}
                Start-Sleep -Milliseconds ([int][Math]::Min(200,$remainingWait*1000))
                $remainingWait=[Math]::Min($IntervalSeconds-($watch.Elapsed.TotalSeconds-$sampleClock),$DurationSeconds-$watch.Elapsed.TotalSeconds)
            }
            if($manifest.CollectionStatus -eq 'Interrupted'){break}
        }
        if($manifest.CollectionStatus -ne 'Interrupted'){$manifest.CollectionStatus='Complete'}
    }catch{$manifest.Error=$_.Exception.Message;throw}
    finally{
        $watch.Stop();$manifest.CompletedAt=[DateTimeOffset]::Now.ToString('o')
        try{& $save
            $html='<html><meta charset="utf-8"><h1>Bounded observation</h1><p>'+[Net.WebUtility]::HtmlEncode($manifest.CollectionStatus+' - '+$manifest.Limitation)+'</p>'
            foreach($ref in $manifest.Samples){$html+='<p><a href="'+$ref.Path+'">'+[Net.WebUtility]::HtmlEncode($ref.StartedAt)+'</a> '+[Net.WebUtility]::HtmlEncode($ref.Status+'; counter discontinuities: '+$ref.CounterDiscontinuities)+'</p><details><summary>Changes and coverage</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json -InputObject $ref.Changes -Depth 6))+'</pre></details>'}
            $html+='<details><summary>Session metadata and user report</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $manifest -Depth 16))+'</pre></details></html>'
            Set-AtomicText (Join-Path $directory 'summary.html') $html
        }catch{Write-Warning 'Final observation checkpoint failed; earlier files remain recoverable.'}
    }
    [pscustomobject]@{Directory=$directory;Evidence=$manifest}
}
