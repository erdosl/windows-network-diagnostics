# Field comparison contract 1. Indexes select rows within a sample only.
function ConvertTo-ObservationFieldValue {
    param($Value,[string]$Field)
    if($null -eq $Value){return $null}
    if($Field -in @('IPAddress','NextHop','ServerAddresses')){
        $items=@(foreach($v in @($Value)){$ip=$null;if([Net.IPAddress]::TryParse([string]$v,[ref]$ip)){$ip.ToString()}else{$v}})
        if($Field -eq 'ServerAddresses'){return ,$items};return $items[0]
    }
    if($Field -eq 'DestinationPrefix'){$parts=[string]$Value -split '/';if($parts.Count -eq 2){$prefix=Get-LogicalPrefix $parts[0] $parts[1];if($prefix){return $prefix}}}
    if($Field -eq 'AddressFamily'){return Get-NetworkDisplayLabel AddressFamily $Value}
    if($Field -eq 'ConnectionState'){return Get-NetworkDisplayLabel $Field $Value}
    if($Field -eq 'AddressState'){$labels=@{'0'='Invalid';'1'='Tentative';'2'='Duplicate';'3'='Deprecated';'4'='Preferred'};if($labels.ContainsKey([string]$Value)){return $labels[[string]$Value]}}
    $Value
}

function Get-ObservationFieldState {
    param($Checks,[string]$Name,[string]$CollectionStatus)
    $fields=@{Adapters=@('Status');IPAddresses=@('IPAddress','PrefixLength','AddressState');DNSServers=@('AddressFamily','ServerAddresses');Routes=@('DestinationPrefix','NextHop','RouteMetric','InterfaceMetric');InterfacesAndMetrics=@('AddressFamily','ConnectionState','InterfaceMetric')}
    $keys=@{Adapters=@();IPAddresses=@('IPAddress');DNSServers=@('AddressFamily');Routes=@('DestinationPrefix','NextHop');InterfacesAndMetrics=@('AddressFamily')}
    $inventory=@($Checks | Where-Object Name -eq 'Adapters');$source=@($Checks | Where-Object Name -eq $Name)
    $issues=@();$records=@();$ids=@()
    $ok=$inventory.Count -eq 1 -and $inventory[0].Status -eq 'Success' -and $inventory[0].Data -is [array] -and $source.Count -eq 1 -and $source[0].Status -eq 'Success' -and $source[0].Data -is [array]
    if($ok){
        $identityCounts=@{}
        foreach($a in $inventory[0].Data){
            $id=Get-ContextIdentity $a.InterfaceGuid
            if(-not $id){$issues+='Unknown inventoried GUID.';continue}
            if($identityCounts.ContainsKey($id)){$identityCounts[$id]++;$issues+='Duplicate inventoried GUID.'}else{$identityCounts[$id]=1}
        }
        $ids=@($identityCounts.Keys | Where-Object {$identityCounts[$_] -eq 1} | Sort-Object)
        $ci=[array]::IndexOf(@($Checks),$source[0])
        for($i=0;$i -lt $source[0].Data.Count;$i++){
            $row=$source[0].Data[$i];$matches=@($inventory[0].Data | Where-Object {$null -ne $row.InterfaceIndex -and $_.InterfaceIndex -eq $row.InterfaceIndex})
            $id=$null;if($matches.Count -eq 1){$id=Get-ContextIdentity $matches[0].InterfaceGuid}
            if(-not $id -or $id -notin $ids){$issues+="/Checks/$ci/Data/$i has no unique inventoried identity.";continue}
            $values=[ordered]@{};$missing=@()
            foreach($field in $fields[$Name]){if($row.PSObject.Properties[$field]){$values[$field]=ConvertTo-ObservationFieldValue $row.$field $field}else{$missing+=$field}}
            if($missing.Count){$issues+="/Checks/$ci/Data/$i missing fields: $($missing -join ', ')."}
            $key=@($keys[$Name] | ForEach-Object {$values[$_]})
            $keyMissing=@($keys[$Name] | Where-Object {$_ -in $missing -or $null -eq $values[$_]})
            if($keyMissing.Count){$issues+="/Checks/$ci/Data/$i lacks record identity fields.";continue}
            $records+=[pscustomobject]@{Identity=$id;Key=(ConvertTo-Json -InputObject $key -Compress);Values=[pscustomobject]$values;Missing=$missing;Path="/Checks/$ci/Data/$i"}
        }
    }else{$issues+='Required inventory or source unavailable/ambiguous.'}
    [pscustomobject]@{ContractVersion=1;Status=$(if($ok){'Success'}else{'Not assessed'});CollectionStatus=$CollectionStatus;Identities=$ids;Records=$records;Reasons=$issues}
}

function Compare-ObservationFields {
    param($Before,$After,[string]$Name,[string]$BeforeArtifact,[string]$AfterArtifact)
    $changes=@();$reasons=@($Before.Reasons)+@($After.Reasons)
    $sufficient=$Before.Status -eq 'Success' -and $After.Status -eq 'Success'
    if($sufficient){
        $ids=@(@($Before.Identities)+@($After.Identities)|Sort-Object -Unique)
        foreach($id in $ids){
            if($id -notin $Before.Identities -or $id -notin $After.Identities){$reasons+="Adapter $id has no established counterpart; no removal inferred.";continue}
            $left=@($Before.Records|Where-Object Identity -eq $id);$right=@($After.Records|Where-Object Identity -eq $id)
            $keys=@(@($left.Key)+@($right.Key)|Sort-Object -Unique)
            foreach($key in $keys){
                $old=@($left|Where-Object Key -ceq $key);$now=@($right|Where-Object Key -ceq $key)
                if($old.Count -gt 1 -or $now.Count -gt 1){$reasons+="Adapter $id has duplicate record identity $key.";continue}
                if(-not $old.Count -or -not $now.Count){
                    if($Before.CollectionStatus -ne 'Complete' -or $After.CollectionStatus -ne 'Complete' -or $reasons.Count){$reasons+='Record absence has insufficient collection coverage.';continue}
                    $changes+=[pscustomobject]@{Identity=$id;Field='Record';Outcome=$(if($old.Count){'Removed'}else{'Added'});Before=$old[0].Values;After=$now[0].Values;BeforeArtifact=$BeforeArtifact;AfterArtifact=$AfterArtifact;BeforePath=$old[0].Path;AfterPath=$now[0].Path};continue
                }
                foreach($field in @(@($old[0].Values.PSObject.Properties.Name)+@($now[0].Values.PSObject.Properties.Name)|Sort-Object -Unique)){
                    if($field -in $old[0].Missing -or $field -in $now[0].Missing){$reasons+="Adapter $id field $field is missing.";continue}
                    $a=$old[0].Values.$field;$b=$now[0].Values.$field
                    if((ConvertTo-Json -InputObject $a -Compress) -ceq (ConvertTo-Json -InputObject $b -Compress)){continue}
                    $changes+=[pscustomobject]@{Identity=$id;Field=$field;Outcome='Changed';Before=$a;After=$b;BeforeArtifact=$BeforeArtifact;AfterArtifact=$AfterArtifact;BeforePath=$old[0].Path;AfterPath=$now[0].Path}
                }
            }
        }
    }
    [pscustomobject]@{Source=$Name;FieldComparisonVersion=1;Outcome=$(if($changes.Count){'Changed'}elseif($reasons.Count -or -not $sufficient){'Not assessed'}else{'Unchanged'});Coverage=$(if($reasons.Count -or -not $sufficient){'Partial'}else{'Complete'});ChangedFields=$changes;Reasons=$reasons;Limitation='GUID association within this run; no continuity between sample instants or event causation is established.'}
}
