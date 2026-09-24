function Get-ObservationDhcpState {
    param($Checks)
    $required=@('DHCPEnabled','DHCPServer','DefaultIPGateway','DNSServerSearchOrder','DNSDomain','DHCPLeaseObtained','DHCPLeaseExpires')
    $sources=@($Checks | Where-Object Name -eq 'DHCPAndGateways')
    $inventory=@($Checks | Where-Object Name -eq 'Adapters')
    $records=@();$reasons=@()
    if($sources.Count -ne 1 -or $sources[0].Status -ne 'Success' -or $sources[0].Data -isnot [array]){
        return [pscustomobject]@{ContractVersion=3;Status='Not assessed';Records=@();Reasons=@('DHCP source missing, failed or ambiguous.')}
    }
    $inventoryOk=$inventory.Count -eq 1 -and $inventory[0].Status -eq 'Success' -and $inventory[0].Data -is [array]
    $ci=[array]::IndexOf(@($Checks),$sources[0])
    foreach($row in $sources[0].Data){
        $di=$records.Count;$path="/Checks/$ci/Data/$di";$issues=@();$id=Get-ContextIdentity $row.SettingID
        $adapters=@()
        if($inventoryOk){
            $adapters=@($inventory[0].Data | Where-Object {($id -and (Get-ContextIdentity $_.InterfaceGuid) -eq $id) -or ($null -ne $row.InterfaceIndex -and $_.InterfaceIndex -eq $row.InterfaceIndex)})
        }
        $adapterId=$null;if($adapters.Count -eq 1){$adapterId=Get-ContextIdentity $adapters[0].InterfaceGuid}
        $code=$null
        if(-not $inventoryOk){$code='InventoryUnavailable'}
        elseif($adapters.Count -eq 0){$code='UnmatchedConfiguration'}
        elseif($adapters.Count -ne 1){$code='AmbiguousInventoryIdentity'}
        elseif(($row.SettingID -and -not $id) -or ($adapters[0].InterfaceGuid -and -not $adapterId) -or (-not $id -and -not $adapterId)){$code='MissingOrInvalidIdentity'}
        elseif($id -and $adapterId -and $id -ne $adapterId){$code='ConflictingIdentity'}
        if($code){$issues+=[pscustomobject]@{Code=$code;Path=$path;Explanation='Configuration cannot be attributed uniquely to current adapter inventory.'}}
        if(-not $id -and -not $code){$id=$adapterId}
        $values=[ordered]@{}
        foreach($field in $required){
            if(-not $row.PSObject.Properties[$field]){$issues+=[pscustomobject]@{Code='MissingProperty';Path=$path;Explanation="Missing property $field"}}
            else{$values[$field]=$row.$field}
        }
        $records+=[pscustomobject]@{Identity=$id;InterfaceIndex=$row.InterfaceIndex;Context=$row | Select-Object Description,IPEnabled,InterfaceIndex,SettingID
            AdapterContext=@($adapters | Select-Object Name,InterfaceGuid,InterfaceIndex,Status);Values=[pscustomobject]$values;Path=$path;Reasons=$issues}
    }
    foreach($record in $records){
        if($record.Identity -and @($records | Where-Object Identity -eq $record.Identity).Count -gt 1){
            $record.Reasons+= [pscustomobject]@{Code='DuplicateConfigurationIdentity';Path=$record.Path;Explanation='Multiple configuration records share this identity.'}
        }
    }
    [pscustomobject]@{ContractVersion=3;Status=$(if(-not $records.Count){'Not assessed'}elseif(@($records | Where-Object {$_.Reasons.Count}).Count){'Partial'}else{'Success'});Records=$records;Reasons=$reasons}
}

function Compare-ObservationDhcpState {
    param($Before,$After,[string]$BeforeArtifact='Before',[string]$AfterArtifact='After')
    $results=@();$details=@();$reasons=@()
    if($Before.ContractVersion -ne 3 -or $After.ContractVersion -ne 3){
        $reasons+= [pscustomobject]@{Code='ContractUnavailable';Artifact=$BeforeArtifact+' / '+$AfterArtifact;Explanation='Comparison state contract 3 required; rederive from raw checks.'}
    } else {
        foreach($side in @('Before','After')){
            $state=Get-Variable $side -ValueOnly
            foreach($reason in $state.Reasons){$reasons+=[pscustomobject]@{Code='SourceUnavailable';Artifact=$(if($side -eq 'Before'){$BeforeArtifact}else{$AfterArtifact});Explanation=$reason}}
        }
        $ids=@(@($Before.Records.Identity)+@($After.Records.Identity) | Where-Object {$_} | Sort-Object -Unique)
        # Unidentified records must remain individual coverage rows, never be joined by position.
        $groups=@()
        foreach($id in $ids){$groups+=[pscustomobject]@{Identity=$id;Old=@($Before.Records | Where-Object Identity -eq $id);Now=@($After.Records | Where-Object Identity -eq $id)}}
        foreach($r in @($Before.Records | Where-Object {-not $_.Identity})){$groups+=[pscustomobject]@{Identity=$null;Old=@($r);Now=@()}}
        foreach($r in @($After.Records | Where-Object {-not $_.Identity})){$groups+=[pscustomobject]@{Identity=$null;Old=@();Now=@($r)}}
        foreach($group in $groups){
            $issues=@();$changes=@();$outcome='Not assessed'
            foreach($side in @('Old','Now')){
                $artifact=$(if($side -eq 'Old'){$BeforeArtifact}else{$AfterArtifact})
                foreach($r in $group.$side){foreach($issue in $r.Reasons){$issues+=[pscustomobject]@{Code=$issue.Code;Artifact=$artifact;Path=$issue.Path;Explanation=$issue.Explanation}}}
                if($group.$side.Count -ne 1){$issues+=[pscustomobject]@{Code='MissingOrAmbiguousCounterpart';Artifact=$artifact;Path=$null;Explanation='No unique configuration counterpart; absence does not establish removal.'}}
            }
            if(-not $issues.Count){
                $old=$group.Old[0];$now=$group.Now[0];$outcome='Unchanged'
                foreach($field in $now.Values.PSObject.Properties.Name){
                    $left=$old.Values.$field;$right=$now.Values.$field
                    if((ConvertTo-Json -InputObject $left -Depth 8 -Compress) -ceq (ConvertTo-Json -InputObject $right -Depth 8 -Compress)){continue}
                    $lease=$field -in @('DHCPLeaseObtained','DHCPLeaseExpires')
                    if(-not $lease){$outcome='Changed'}elseif($outcome -eq 'Unchanged'){$outcome='LeaseRefreshed'}
                    $changes+=[pscustomobject]@{Identity=$group.Identity;Field=$field;Before=$left;After=$right;LeaseField=$lease
                        BeforeValueState=$(if($null -eq $left){'ObservedNull'}elseif($left -is [array] -and $left.Count -eq 0){'ObservedEmpty'}else{'Value'})
                        AfterValueState=$(if($null -eq $right){'ObservedNull'}elseif($right -is [array] -and $right.Count -eq 0){'ObservedEmpty'}else{'Value'})
                        BeforePath=$old.Path;AfterPath=$now.Path;BeforeArtifact=$BeforeArtifact;AfterArtifact=$AfterArtifact}
                }
            }
            $results+=[pscustomobject]@{Identity=$group.Identity;Outcome=$outcome;ChangedFields=$changes;Reasons=$issues
                BeforeContext=@($group.Old.Context);AfterContext=@($group.Now.Context)
                BeforeAdapterContext=@($group.Old.AdapterContext | Where-Object {$null -ne $_})
                AfterAdapterContext=@($group.Now.AdapterContext | Where-Object {$null -ne $_})
                BeforeEvidence=@($group.Old | ForEach-Object {[pscustomobject]@{Artifact=$BeforeArtifact;Path=$_.Path}})
                AfterEvidence=@($group.Now | ForEach-Object {[pscustomobject]@{Artifact=$AfterArtifact;Path=$_.Path}})}
            $details+=$changes;$reasons+=$issues
        }
    }
    $coverage=$(if(-not $results.Count -or $reasons.Count){'Partial'}else{'Complete'})
    $outcome='Not assessed'
    if(@($results | Where-Object Outcome -eq 'Changed').Count){$outcome='Changed'}
    elseif(@($results | Where-Object Outcome -eq 'LeaseRefreshed').Count){$outcome='LeaseRefreshed'}
    elseif($coverage -eq 'Complete'){$outcome='Unchanged'}
    [pscustomobject]@{Source='DHCPAndGateways';Outcome=$outcome;Coverage=$coverage;Adapters=$results;BeforeStatus=$Before.Status;AfterStatus=$After.Status;ChangedFields=$details;Reasons=$reasons
        Limitation='Known adapter results and coverage are separate. No removal, competing DHCP server, malicious behavior or current-path fault is inferred. LeaseRefreshed describes timestamps, not a captured exchange.'}
}
function Get-ObservationState {
    param($Checks)
    $result=[ordered]@{}
    $fields=@{
        Adapters=@('InterfaceGuid','InterfaceIndex','Status','MacAddress')
        IPAddresses=@('InterfaceIndex','IPAddress','PrefixLength','AddressState','PrefixOrigin','SuffixOrigin')
        DHCPAndGateways=@() # Dedicated identity/field-presence normalization above.
        Routes=@('InterfaceIndex','DestinationPrefix','NextHop','RouteMetric','InterfaceMetric','Protocol')
        DNSServers=@('InterfaceIndex','AddressFamily','ServerAddresses')
        InterfacesAndMetrics=@('InterfaceIndex','AddressFamily','ConnectionState','InterfaceMetric')
    }
    foreach($name in @($fields.Keys | Sort-Object)){
        if($name -eq 'DHCPAndGateways'){$result[$name]=Get-ObservationDhcpState $Checks;continue}
        $check=@($Checks | Where-Object Name -eq $name)
        if($check.Count -ne 1 -or $check[0].Status -ne 'Success' -or $check[0].Data -isnot [array]){$result[$name]=[pscustomobject]@{Status='Not assessed';Value=$null};continue}
        $values=@($check[0].Data | Select-Object -Property $fields[$name] | ForEach-Object {ConvertTo-Json $_ -Depth 8 -Compress} | Sort-Object)
        $result[$name]=[pscustomobject]@{Status='Success';Value=$values}
    }
    [pscustomobject]$result
}

function Compare-ObservationState {
    param($Before,$After,[string]$BeforeArtifact='Before',[string]$AfterArtifact='After')
    foreach($property in $After.PSObject.Properties){
        $name=$property.Name;$left=$Before.$name;$right=$property.Value
        if($name -eq 'DHCPAndGateways'){Compare-ObservationDhcpState $left $right $BeforeArtifact $AfterArtifact;continue}
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

function ConvertTo-ObservationChangesHtml {
    param($Changes)
    $html='<table><tr><th>Identity / source</th><th>Outcome</th><th>Coverage / details</th></tr>'
    foreach($change in $Changes){
        $html+='<tr><td>'+[Net.WebUtility]::HtmlEncode($change.Source)+'</td><td>'+[Net.WebUtility]::HtmlEncode($change.Outcome)+'</td><td>'+[Net.WebUtility]::HtmlEncode($change.Coverage)+'</td></tr>'
        foreach($adapter in $change.Adapters){
            $description=(@($adapter.ChangedFields.Field)+@($adapter.Reasons | ForEach-Object {$_.Artifact+': '+$_.Explanation})) -join '; '
            $html+='<tr><td>'+[Net.WebUtility]::HtmlEncode($adapter.Identity)+'</td><td>'+[Net.WebUtility]::HtmlEncode($adapter.Outcome)+'</td><td>'+[Net.WebUtility]::HtmlEncode($description)+'</td></tr>'
        }
    }
    $html+'</table><details><summary>Changes, context and evidence references</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json -InputObject @($Changes) -Depth 12))+'</pre></details>'
}

function Get-CounterDeltas {
    param($Before,$After,[double]$ElapsedSeconds)
    $names=@('ReceivedBytes','SentBytes','ReceivedUnicastPackets','SentUnicastPackets','ReceivedPacketErrors','OutboundPacketErrors','ReceivedDiscardedPackets','OutboundDiscardedPackets')
    foreach($check in @($After.Checks | Where-Object Name -like 'AdapterStatistics:*')){
        $rows=@($check.Data);$row=$null;if($rows.Count -eq 1){$row=$rows[0]}
        $old=@($Before.Checks | Where-Object { $_.Name -like 'AdapterStatistics:*' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data} | Where-Object {$row.InterfaceGuid -and $_.InterfaceGuid -eq $row.InterfaceGuid})
        $discontinuity=$check.Status -ne 'Success' -or $old.Count -ne 1 -or -not $row.InterfaceGuid -or $ElapsedSeconds -le 0
        $counterSeconds=$null;$intervalBasis='Unassessed: shared same-run monotonic counter timing unavailable'
        if($old.Count -eq 1 -and $Before.RunId -and $Before.RunId -eq $After.RunId -and
            $row.CounterTiming.RunId -eq $After.RunId -and $old[0].CounterTiming.RunId -eq $Before.RunId -and
            $row.CounterTiming.Basis -eq 'SystemStopwatch' -and $old[0].CounterTiming.Basis -eq 'SystemStopwatch'){
            $counterSeconds=$row.CounterTiming.StartSeconds-$old[0].CounterTiming.StartSeconds
            $intervalBasis='Same-run system Stopwatch query starts; provider sampling occurs within retained query windows'
            if($counterSeconds -le 0 -or $row.CounterTiming.StartSeconds -lt $old[0].CounterTiming.EndSeconds){$counterSeconds=$null}
        }
        if($null -eq $counterSeconds){$discontinuity=$true}
        $links=@($Before.Checks+$After.Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data} | Where-Object InterfaceGuid -eq $row.InterfaceGuid)
        if($links.Count -ne 2 -or $links[0].Status -ne $links[1].Status){$discontinuity=$true}
        foreach($name in $names){
            $a=$null;$b=$null;if($old.Count -eq 1){$a=$old[0].Fields.$name};if($row){$b=$row.Fields.$name}
            $delta=$null;$rate=$null;$status='Unavailable'
            if($null -ne $a -and $null -ne $b){
                $status=$(if($null -eq $counterSeconds){'Not assessed'}else{'Discontinuity'})
                if(-not $discontinuity -and [decimal]$b -ge [decimal]$a){$status='Delta';$delta=[decimal]$b-[decimal]$a;$rate=[double]$delta/$counterSeconds}
            }
            [pscustomobject]@{TimingContractVersion=1;InterfaceGuid=$row.InterfaceGuid;Counter=$name;Before=$a;After=$b;ElapsedSeconds=$counterSeconds;IntervalBasis=$intervalBasis;Status=$status;Delta=$delta;PerSecond=$rate;Limitation='Approximate rate over query-start intervals; provider samples occur within the retained query windows. An unseen reset may be undetectable. Errors/discards do not prove a physical fault.'}
        }
    }
}

function Invoke-ObservationRun {
    param([string]$RepositoryRoot,[ValidateRange(10,600)][int]$DurationSeconds=60,
        [ValidateRange(5,120)][int]$IntervalSeconds=10,[ValidateRange(1,60)][int]$CheckTimeoutSeconds=10,
        [string]$IncidentContextPath,[scriptblock]$CheckExecutor,[scriptblock]$CancelRequested,
        [string]$TestOutputRoot,[scriptblock]$ElapsedClock,[scriptblock]$WaitAction,[scriptblock]$WallClock)
    $wall={if($WallClock){& $WallClock}else{[DateTimeOffset]::Now}}
    $identity=New-SnapshotIdentity
    $outputRoot=Join-Path $RepositoryRoot 'output';if($TestOutputRoot){$outputRoot=$TestOutputRoot}
    $directory=Join-Path $outputRoot ('observation-'+($identity.ComputerName -replace '[^A-Za-z0-9_.-]','_')+'-'+$identity.RunId)
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $manifest=[pscustomobject]@{SchemaVersion=9;ObservationComparisonVersion=3;Mode='Observation';Identity=$identity;CollectionStatus='Incomplete';CompletedAt=$null
        DurationSeconds=$DurationSeconds;IntervalSeconds=$IntervalSeconds;Samples=@();IncidentContext=$null;Error=$null
        Timing=[pscustomobject]@{ContractVersion=1;Basis='Parent run Stopwatch';CollectionStartedAt=(& $wall).ToString('o');CollectionEndedAt=$null;CollectionElapsedSeconds=$null;FinalizationElapsedSeconds=$null;MeasuredElapsedSeconds=$null;WallClockCollectionSeconds=$null;WallMinusMonotonicSeconds=$null;TerminationReason=$null;FinalizationMeasuredThrough='Before final metadata writes; those writes are excluded'}
        Limitation='Sequential samples, no overlap or queue. Transitions between samples can be missed. A failed sample is not unchanged state. No current-path fault is inferred.'}
    $save={Set-AtomicText (Join-Path $directory 'evidence.json') (ConvertTo-Json -InputObject $manifest -Depth 16)}
    $origin=[Diagnostics.Stopwatch]::GetTimestamp();$elapsed={if($ElapsedClock){& $ElapsedClock}else{([Diagnostics.Stopwatch]::GetTimestamp()-$origin)/[double][Diagnostics.Stopwatch]::Frequency}};$previous=$null;$eventEnds=@{};$seen=@{};$sequence=0
    $timingContext=[pscustomobject]@{RunId=$identity.RunId;OriginTicks=$origin;Frequency=[Diagnostics.Stopwatch]::Frequency}
    try{
        & $save
        if($IncidentContextPath){
            try{$manifest.IncidentContext=Invoke-BoundedCheck ([pscustomobject]@{Name='IncidentContext';FunctionName='Read-IncidentContext';Arguments=@{Path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IncidentContextPath)}}) (Join-Path $RepositoryRoot 'src') $directory ([Math]::Min($DurationSeconds,$CheckTimeoutSeconds))}
            catch{$failure=$_;$manifest.IncidentContext=Invoke-DiagnosticCheck 'IncidentContext' {throw $failure}}
            & $save
        }
        while([Math]::Floor($DurationSeconds-(& $elapsed)) -ge 1){
            if($CancelRequested -and (& $CancelRequested)){ $manifest.CollectionStatus='Interrupted';break }
            $sampleStart=(& $wall);$sampleClock=(& $elapsed)
            $sample=[pscustomobject]@{SchemaVersion=9;ObservationComparisonVersion=3;RunId=$identity.RunId;Sequence=$sequence;StartedAt=$sampleStart.ToString('o');CompletedAt=$null;CollectionStatus='Incomplete';Checks=@();Changes=@();CounterDeltas=@();ActualIntervalSeconds=$null}
            $sample | Add-Member NoteProperty Timing ([pscustomobject]@{ContractVersion=1;Basis='Parent run Stopwatch';StartedElapsedSeconds=$sampleClock;CompletedElapsedSeconds=$null;IntervalBasis='Same-run monotonic sample starts'})
            $sample | Add-Member NoteProperty StatisticsCoverage ([pscustomobject]@{ContractVersion=1;BatchExecutionStatus='NotCollected';ExpectedAdapters=$null;UsableAdapters=0;Status='Not assessed';EvidencePath=$null;Limitation='Adapter inventory or statistics batch not collected; no usable counter coverage established.'})
            if($previous){$sample.ActualIntervalSeconds=$sampleClock-$previous.Timing.StartedElapsedSeconds}
            $relative='sample-{0:D4}.json' -f $sequence
            $samplePath=Join-Path $directory $relative
            $execute={param($definition)
                $remaining=[int][Math]::Floor($DurationSeconds-(& $elapsed))
                if($remaining -lt 1){return $false}
                $timeout=[Math]::Min($CheckTimeoutSeconds,$remaining)
                if(-not $sample.Checks.Count){
                    Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
                    $manifest.Samples+= [pscustomobject]@{Path=$relative;Sequence=$sequence;StartedAt=$sample.StartedAt;Status='Incomplete';ActualIntervalSeconds=$sample.ActualIntervalSeconds;Changes=@();CounterDiscontinuities=0;Sha256=$null}
                    & $save
                    # Persistence can consume the remaining budget. Roll back only this
                    # never-attempted sample; the run checkpoint remains recoverable.
                    $remaining=[int][Math]::Floor($DurationSeconds-(& $elapsed))
                    if($remaining -lt 1){
                        $manifest.Samples=@($manifest.Samples | Where-Object Path -ne $relative)
                        & $save
                        if(Test-Path -LiteralPath $samplePath){Remove-Item -LiteralPath $samplePath -ErrorAction Stop}
                        return $false
                    }
                    $timeout=[Math]::Min($CheckTimeoutSeconds,$remaining)
                }
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
            $adapters=@($sample.Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data})
            if($adapters.Count){
                $sample.StatisticsCoverage.ExpectedAdapters=$adapters.Count
                if(-not (& $execute ([pscustomobject]@{Name='ObservationStatistics';FunctionName='Invoke-ObservationStatistics';Arguments=@{Adapters=$adapters;TimingContext=$timingContext}}))){$complete=$false}
                else{
                    $batch=$sample.Checks[-1];$batchPath='/Checks/'+($sample.Checks.Count-1)
                    foreach($adapter in $adapters){
                        $rows=@($batch.Data | Where-Object {$_.AdapterIdentity.InterfaceIndex -eq $adapter.InterfaceIndex -and $_.AdapterIdentity.InterfaceGuid -eq $adapter.InterfaceGuid})
                        $status=$batch.Status;$data=@();$error=$batch.Error
                        if($batch.Status -eq 'Success'){
                            if($rows.Count -eq 1){$status=$rows[0].Status;$data=@($rows[0].Data);$error=$rows[0].Error}
                            else{$status='Unavailable';$error=[pscustomobject]@{Explanation='Batch result missing or ambiguous; no counters attributed.'}}
                        }
                        $sample.Checks+=[pscustomobject]@{Name=('AdapterStatistics:'+$adapter.InterfaceIndex);Status=$status;Data=$data;Error=$error;EvidencePath=$batchPath;AdapterIdentity=$adapter | Select-Object Name,InterfaceIndex,InterfaceGuid}
                    }
                    $counterFields=@('ReceivedBytes','SentBytes','ReceivedUnicastPackets','SentUnicastPackets','ReceivedPacketErrors','OutboundPacketErrors','ReceivedDiscardedPackets','OutboundDiscardedPackets')
                    $usable=@($sample.Checks | Where-Object {
                        $_.Name -like 'AdapterStatistics:*' -and $_.Status -eq 'Success' -and @($_.Data | Where-Object {
                            $counterRow=$_;@($counterFields | Where-Object {$null -ne $counterRow.Fields.$_}).Count -gt 0
                        }).Count -gt 0
                    }).Count
                    $sample.StatisticsCoverage=[pscustomobject]@{ContractVersion=1;BatchExecutionStatus=$batch.Status;ExpectedAdapters=$adapters.Count;UsableAdapters=$usable;Status=$(if($usable -eq $adapters.Count){'Complete'}elseif($usable){'Partial'}else{'Unavailable'});EvidencePath=$batchPath;Limitation='Execution success does not establish usable counter coverage; individual fields may still be absent.'}
                    Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
                }
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
            if(-not $sample.Checks.Count){break}
            $state=Get-ObservationState $sample.Checks
            if($previous){
                $sample.Changes=@(Compare-ObservationState (Get-ObservationState $previous.Checks) $state ('sample-{0:D4}.json' -f ($sequence-1)) $relative);$sample.CounterDeltas=@(Get-CounterDeltas $previous $sample $sample.ActualIntervalSeconds)
                foreach($change in $sample.Changes){
                    $change | Add-Member NoteProperty BeforeEvidence ([pscustomobject]@{Scope='Observation';RunId=$identity.RunId;Artifact=('sample-{0:D4}.json' -f ($sequence-1));SourceCheck=$change.Source})
                    $change | Add-Member NoteProperty AfterEvidence ([pscustomobject]@{Scope='Observation';RunId=$identity.RunId;Artifact=$relative;SourceCheck=$change.Source})
                }
            }
            if($complete){$sample.CollectionStatus='Complete'}
            $sample.CompletedAt=(& $wall).ToString('o');$sample.Timing.CompletedElapsedSeconds=(& $elapsed)
            Set-AtomicText $samplePath (ConvertTo-Json $sample -Depth 24)
            $manifest.Samples[-1].Status=$sample.CollectionStatus
            $manifest.Samples[-1].Changes=@($sample.Changes | Select-Object Source,Outcome,Coverage,Adapters,ChangedFields,Reasons,BeforeEvidence,AfterEvidence)
            $manifest.Samples[-1].CounterDiscontinuities=@($sample.CounterDeltas | Where-Object Status -eq 'Discontinuity').Count
            $manifest.Samples[-1].Sha256=(Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash
            $manifest.Samples[-1] | Add-Member NoteProperty StatisticsCoverage $sample.StatisticsCoverage
            & $save
            $previous=$sample;$sequence++
            $remainingWait=[Math]::Min($IntervalSeconds-((& $elapsed)-$sampleClock),$DurationSeconds-(& $elapsed))
            while($remainingWait -gt 0){
                if($CancelRequested -and (& $CancelRequested)){$manifest.CollectionStatus='Interrupted';break}
                if($WaitAction){& $WaitAction $remainingWait}else{Start-Sleep -Milliseconds ([int][Math]::Min(200,$remainingWait*1000))}
                $remainingWait=[Math]::Min($IntervalSeconds-((& $elapsed)-$sampleClock),$DurationSeconds-(& $elapsed))
            }
            if($manifest.CollectionStatus -eq 'Interrupted'){break}
        }
        if($manifest.CollectionStatus -ne 'Interrupted'){$manifest.CollectionStatus='Complete'}
    }catch{$manifest.Error=$_.Exception.Message;throw}
    finally{
        $collectionEnd=(& $elapsed);$manifest.Timing.CollectionElapsedSeconds=$collectionEnd
        $manifest.Timing.CollectionEndedAt=(& $wall).ToString('o')
        $manifest.Timing.WallClockCollectionSeconds=([DateTimeOffset]::Parse($manifest.Timing.CollectionEndedAt)-[DateTimeOffset]::Parse($manifest.Timing.CollectionStartedAt)).TotalSeconds
        $manifest.Timing.WallMinusMonotonicSeconds=$manifest.Timing.WallClockCollectionSeconds-$collectionEnd
        $manifest.Timing.TerminationReason=$(if($manifest.Error){'CollectionError'}elseif($manifest.CollectionStatus -eq 'Interrupted'){'Cancelled'}else{'DeadlineBudgetExhausted'})
        $manifest.CompletedAt=(& $wall).ToString('o')
        try{& $save
            $html='<html><meta charset="utf-8"><h1>Bounded observation</h1><p>'+[Net.WebUtility]::HtmlEncode($manifest.CollectionStatus+' - '+$manifest.Limitation)+'</p>'
            $html+='<p>Complete samples: '+@($manifest.Samples | Where-Object Status -eq 'Complete').Count+'; partial samples: '+@($manifest.Samples | Where-Object Status -ne 'Complete').Count+'</p>'
            foreach($ref in $manifest.Samples){$html+='<p><a href="'+$ref.Path+'">'+[Net.WebUtility]::HtmlEncode($ref.StartedAt)+'</a> '+[Net.WebUtility]::HtmlEncode($ref.Status+'; actual interval seconds: '+$ref.ActualIntervalSeconds+'; counter discontinuities: '+$ref.CounterDiscontinuities)+'</p>'+(ConvertTo-ObservationChangesHtml $ref.Changes)}
            $htmlBase=$html
            $html+='<details><summary>Session metadata and user report</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $manifest -Depth 16))+'</pre></details></html>'
            Set-AtomicText (Join-Path $directory 'summary.html') $html
            $manifest.Timing.MeasuredElapsedSeconds=(& $elapsed)
            $manifest.Timing.FinalizationElapsedSeconds=$manifest.Timing.MeasuredElapsedSeconds-$collectionEnd
            $manifest.CompletedAt=(& $wall).ToString('o')
            & $save
            $timingHtml='<h2>Timing and statistics coverage</h2><p>Requested collection seconds: '+$DurationSeconds+'; measured collection seconds: '+$collectionEnd+'; finalization seconds: '+$manifest.Timing.FinalizationElapsedSeconds+'; termination: '+$manifest.Timing.TerminationReason+'. Actual intervals use the parent run Stopwatch. Wall-clock differences alone do not prove a clock adjustment or deadline violation.</p><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $manifest.Timing -Depth 5))+'</pre>'
            foreach($ref in $manifest.Samples){$timingHtml+='<p>Sample '+$ref.Sequence+' statistics: '+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $ref.StatisticsCoverage -Compress))+'</p>'}
            Set-AtomicText (Join-Path $directory 'summary.html') ($htmlBase+$timingHtml+'<details><summary>Session metadata and user report</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $manifest -Depth 16))+'</pre></details></html>')
        }catch{Write-Warning 'Final observation checkpoint failed; earlier files remain recoverable.'}
    }
    [pscustomobject]@{Directory=$directory;Evidence=$manifest}
}
