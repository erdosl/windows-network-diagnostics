function Get-LogicalPrefix {
    param([string]$Address, $PrefixLength)
    $ip=$null
    if (-not [Net.IPAddress]::TryParse(($Address -split '%')[0],[ref]$ip) -or $null -eq $PrefixLength) { return $null }
    $bytes=$ip.GetAddressBytes(); $bits=0
    if (-not [int]::TryParse([string]$PrefixLength,[ref]$bits) -or $bits -lt 0 -or $bits -gt $bytes.Length*8) { return $null }
    for ($i=0;$i -lt $bytes.Length;$i++) {
        $keep=[Math]::Min(8,[Math]::Max(0,$bits-$i*8))
        $bytes[$i]=$bytes[$i] -band (256 - [int][Math]::Pow(2,8-$keep))
    }
    ([Net.IPAddress]::new($bytes)).ToString() + '/' + $bits
}

function Get-NeighbourStateLabel {
    param($Value)
    $labels=@{ '0'='Unreachable'; '1'='Incomplete'; '2'='Probe'; '3'='Delay'; '4'='Stale'; '5'='Reachable'; '6'='Permanent' }
    if ($null -eq $Value) { return 'Unknown (missing)' }
    if ($labels.ContainsKey([string]$Value)) { return $labels[[string]$Value] }
    if ([string]$Value -in $labels.Values) { return [string]$Value }
    'Unknown (' + [string]$Value + ')'
}

function Get-NeighbourEligibility {
    param($Neighbour,[object[]]$Addresses)
    $ip=$null
    if (-not [Net.IPAddress]::TryParse([string]$Neighbour.IPAddress,[ref]$ip)) { return 'Invalid address' }
    $bytes=$ip.GetAddressBytes()
    if ($ip.IsIPv6Multicast -or ($bytes.Length -eq 4 -and ($bytes[0] -ge 224 -and $bytes[0] -le 239))) { return 'Multicast' }
    if ($ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)) { return 'Unspecified address' }
    if ($ip.Equals([Net.IPAddress]::Broadcast)) { return 'Broadcast' }
    if ($bytes.Length -eq 4) {
        foreach ($address in @($Addresses | Where-Object InterfaceIndex -eq $Neighbour.InterfaceIndex)) {
            $prefix=Get-LogicalPrefix $address.IPAddress $address.PrefixLength
            if ($prefix -and $prefix -notmatch ':' -and [int]$address.PrefixLength -lt 31) {
                $network=[Net.IPAddress]::Parse(($prefix -split '/')[0]).GetAddressBytes()
                for ($i=0;$i -lt 4;$i++) {
                    $keep=[Math]::Min(8,[Math]::Max(0,[int]$address.PrefixLength-$i*8))
                    $network[$i]=$network[$i] -bor ([int][Math]::Pow(2,8-$keep)-1)
                }
                if ($ip.Equals([Net.IPAddress]::new($network))) { return 'Broadcast' }
            }
        }
    }
    $mac=([string]$Neighbour.LinkLayerAddress) -replace '[-:]',''
    if ($mac -notmatch '^[0-9a-fA-F]{12}$' -or $mac -match '^0{12}$' -or ([Convert]::ToInt32($mac.Substring(0,2),16) -band 1)) { return 'No usable unicast MAC' }
    'Eligible observation (not an identified physical device)'
}

function Get-LogicalNetworkModel {
    param($Evidence)
    $nodes=[Collections.Generic.List[object]]::new(); $edges=[Collections.Generic.List[object]]::new()
    $coverage=[Collections.Generic.List[object]]::new(); $interfaces=@{}; $subnets=@{}
    $checks=@($Evidence.Checks)
    $addresses=@($checks | Where-Object { $_.Name -eq 'IPAddresses' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    function New-Provenance { param($Check,$Reference,$Type,$Limitation)
        [pscustomobject]@{ CheckName=$Check.Name; EvidenceReference=$Reference; EvidenceType=$Type
            StartedAt=$(if ($Check.StartedAt) {$Check.StartedAt} else {$Evidence.StartedAt})
            CompletedAt=$(if ($Check.CompletedAt) {$Check.CompletedAt} else {$Evidence.CompletedAt})
            Limitation=$Limitation }
    }
    function Add-Node { param($Id,$Kind,$InterfaceIndex,$Label,$Data,$Support)
        $nodes.Add([pscustomobject]@{Id=$Id;Kind=$Kind;InterfaceIndex=$InterfaceIndex;Label=$Label;Data=$Data;Support=@($Support)})
    }
    function Add-Edge { param($From,$To,$Kind,$Support)
        $edges.Add([pscustomobject]@{Id=('relationship:'+ $edges.Count);From=$From;To=$To;Kind=$Kind;Support=@($Support)})
    }
    function Ensure-Interface { param($Index,$Support)
        $key=[string]$Index
        if (-not $key) { $key='Unknown' }
        if (-not $interfaces.ContainsKey($key)) {
            $id='interface:'+ $key; $interfaces[$key]=$id
            Add-Node $id 'Interface' $key ('Interface '+$key) $null $Support
            Add-Edge 'computer' $id 'HasInterface' $Support
        }
        $interfaces[$key]
    }
    $identity=[pscustomobject]@{Name='SnapshotIdentity';StartedAt=$Evidence.StartedAt;CompletedAt=$Evidence.CompletedAt}
    Add-Node 'computer' 'Computer' $null $Evidence.ComputerName $null (New-Provenance $identity '/ComputerName' 'observed' 'Identity of the collecting computer; no physical topology inferred.')
    foreach ($name in @('Adapters','IPAddresses','DHCPAndGateways','Routes','Neighbours','WiFiConnection')) {
        $source=@($checks | Where-Object Name -eq $name)
        $coverage.Add([pscustomobject]@{Source=$name;Status=$(if($source.Count){$source[-1].Status}else{'NotCollected'});Limitation=$(if($source.Count -and $source[-1].Status -eq 'Success'){'Snapshot only; not continuous observation.'}else{'Missing usable source evidence limits the map.'})})
    }
    $coverage.Add([pscustomobject]@{Source='PhysicalLayer2';Status='Unknown';Limitation='Unknown Layer 2 infrastructure: switches, ports, cables and physical paths are not established.'})
    $coverage.Add([pscustomobject]@{Source='StructuredWiFiAssociation';Status='Unavailable';Limitation='Localized netsh text remains raw evidence; no structured access-point relationship is inferred.'})
    for ($ci=0;$ci -lt $checks.Count;$ci++) {
        $check=$checks[$ci]
        if ($check.Name -like 'AdapterStatistics*' -or $check.Name -like 'AdapterPowerManagement*') {
            $coverage.Add([pscustomobject]@{Source=$check.Name;Status=$check.Status;Limitation=([string]$check.Error.Explanation+' Single snapshot: cumulative counters are not rates/current faults; power settings were not changed.').Trim()})
        }
        if ($check.Name -like 'Connectivity*') {
            $coverage.Add([pscustomobject]@{Source=$check.Name;Status=$check.Status;Limitation='Only existing probe evidence is used; collection success does not imply probe success.'})
        }
        if ($check.Status -ne 'Success') { continue }
        for ($di=0;$di -lt @($check.Data).Count;$di++) {
            $data=@($check.Data)[$di]; $ref="/Checks/$ci/Data/$di"; $id="evidence:$ci`:$di"
            switch ($check.Name) {
                'Adapters' {
                    $support=New-Provenance $check $ref 'observed' 'Adapter metadata and link state do not establish a physical path.'
                    $ifid=Ensure-Interface $data.InterfaceIndex $support
                    $node=$nodes | Where-Object Id -eq $ifid
                    $node.Label=[string]$data.Name; $node.Data=$data; $node.Support=@($support)
                }
                'IPAddresses' {
                    $support=New-Provenance $check $ref 'configured' 'Assigned address and prefix; interface and scope context retained.'
                    $ifid=Ensure-Interface $data.InterfaceIndex $support
                    Add-Node $id 'Address' $data.InterfaceIndex ($data.IPAddress + '/' + $data.PrefixLength) $data $support
                    Add-Edge $ifid $id 'HasAddress' $support
                    $prefix=Get-LogicalPrefix $data.IPAddress $data.PrefixLength
                    if ($prefix) {
                        $subsupport=New-Provenance $check $ref 'inferred' 'Directly connected subnet inferred from assigned prefix, not verified physical segment; overlapping interfaces stay separate.'
                        $subid='subnet:'+ $data.InterfaceIndex + ':' + $prefix + ':' + (($data.IPAddress -split '%',2 | Select-Object -Skip 1) -join '')
                        if (-not $subnets.ContainsKey($subid)) {
                            $subnets[$subid]=$true
                            Add-Node $subid 'Subnet' $data.InterfaceIndex $prefix ([pscustomobject]@{Prefix=$prefix;ScopeContext=$data.IPAddress}) $subsupport
                        } else { ($nodes | Where-Object Id -eq $subid).Support += $subsupport }
                        Add-Edge $ifid $subid 'AssignedPrefix' $subsupport
                    }
                }
                'Routes' {
                    $support=New-Provenance $check $ref 'configured' 'Candidate route only; configuration does not prove gateway reachability or active route selection.'
                    $ifid=Ensure-Interface $data.InterfaceIndex $support
                    Add-Node $id 'Route' $data.InterfaceIndex ($data.DestinationPrefix+' via '+$data.NextHop) $data $support
                    Add-Edge $ifid $id 'CandidateRoute' $support
                    if ($data.DestinationPrefix -in @('0.0.0.0/0','::/0') -and $data.NextHop -notin @('0.0.0.0','::','')) {
                        Add-Node ($id+':gateway') 'Gateway' $data.InterfaceIndex $data.NextHop $data $support
                        Add-Edge $id ($id+':gateway') 'ConfiguredDefaultGateway' $support
                    }
                }
                'DHCPAndGateways' {
                    $support=New-Provenance $check $ref 'configured' 'Configured gateway from adapter configuration; may duplicate route evidence and does not prove reachability or route use.'
                    $ifid=Ensure-Interface $data.InterfaceIndex $support
                    $gi=0
                    foreach ($gateway in @($data.DefaultIPGateway)) {
                        if (-not $gateway) { $gi++; continue }
                        $gatewaySupport=New-Provenance $check ($ref+'/DefaultIPGateway/'+$gi) 'configured' $support.Limitation
                        Add-Node ($id+':configured-gateway:'+ $gi) 'Gateway' $data.InterfaceIndex $gateway $null $gatewaySupport
                        Add-Edge $ifid ($id+':configured-gateway:'+ $gi) 'ConfiguredGateway' $gatewaySupport
                        $gi++
                    }
                }
                'Neighbours' {
                    $support=New-Provenance $check $ref 'observed' 'Neighbour cache at collection time, not proof of current reachability or a physical device. IP/MAC reuse may reflect ambiguity, proxying or conflict; no diagnosis or device merging.'
                    $ifid=Ensure-Interface $data.InterfaceIndex $support
                    $eligibility=Get-NeighbourEligibility $data $addresses
                    $details=[pscustomobject]@{IPAddress=$data.IPAddress;LinkLayerAddress=$data.LinkLayerAddress;StateRaw=$data.State;StateLabel=Get-NeighbourStateLabel $data.State;Eligibility=$eligibility;IncludedInEndpointObservationCount=$eligibility.StartsWith('Eligible')}
                    Add-Node $id 'NeighbourObservation' $data.InterfaceIndex ($data.IPAddress+' ['+$details.StateLabel+']') $details $support
                    Add-Edge $ifid $id 'CachedNeighbour' $support
                }
            }
            if ($check.Name -like 'Connectivity:*') {
                if ($data.RoutePrediction) {
                    $support=New-Provenance $check ($ref+'/RoutePrediction') 'predicted' 'OS route prediction, not proof of the path taken by the query or socket.'
                    Add-Node ($id+':prediction') 'RoutePrediction' $null $data.Destination $data.RoutePrediction $support
                    Add-Edge 'computer' ($id+':prediction') 'PredictedRoute' $support
                    foreach ($candidate in @($data.RoutePrediction.Routes)+@($data.RoutePrediction.SourceAddresses)) {
                        if ($null -ne $candidate.InterfaceIndex) {
                            $ifid=Ensure-Interface $candidate.InterfaceIndex $support
                            Add-Edge $ifid ($id+':prediction') 'PredictedInterfaceCandidate' $support
                        }
                    }
                }
                if ($data.ObservedConnection) {
                    $socket=$data.ObservedConnection
                    $support=New-Provenance $check ($ref+'/ObservedConnection') 'observed' 'Socket endpoints were observed during the probe; remote IP remains separate from gateway/MAC identity. Does not establish current connectivity or a physical path.'
                    Add-Node ($id+':socket') 'ObservedSocket' $null ($socket.LocalAddress+' -> '+$socket.RemoteAddress) $socket $support
                    Add-Edge 'computer' ($id+':socket') 'ObservedSocketEndpoints' $support
                    foreach ($match in @($socket.InterfaceMatches)) {
                        $ifid=Ensure-Interface $match.InterfaceIndex $support
                        Add-Edge $ifid ($id+':socket') 'LocalAddressInterfaceMatch' (New-Provenance $check ($ref+'/ObservedConnection/InterfaceMatches') 'inferred' 'Match by observed local address; multiple matches remain ambiguous, not proof of one selected interface.')
                    }
                }
            }
        }
    }
    foreach ($prefix in @('AdapterStatistics','AdapterPowerManagement')) {
        if (-not @($coverage | Where-Object Source -like "$prefix*").Count) { $coverage.Add([pscustomobject]@{Source=$prefix;Status='NotCollected';Limitation='Per-adapter evidence unavailable or not yet collected.'}) }
    }
    [pscustomobject]@{ModelVersion=1;View='Logical network, not physical wiring';Nodes=@($nodes.ToArray());Relationships=@($edges.ToArray());Coverage=@($coverage.ToArray())
        Counts=[pscustomobject]@{Interfaces=$interfaces.Count;Subnets=@($nodes | Where-Object Kind -eq Subnet).Count;NeighbourObservations=@($nodes | Where-Object Kind -eq NeighbourObservation).Count;EligibleEndpointObservations=@($nodes | Where-Object { $_.Kind -eq 'NeighbourObservation' -and $_.Data.IncludedInEndpointObservationCount }).Count}
        Filtering='Broadcast, multicast, unspecified/invalid addresses and unusable MACs excluded from eligible endpoint-observation counts only; raw entries retained. Counts are not physical device counts.'}
}

function ConvertTo-LogicalNetworkHtml {
    param($Model)
    $encode={param($x) [Net.WebUtility]::HtmlEncode([string]$x)}
    $html=[Text.StringBuilder]::new()
    $null=$html.Append('<h2>Logical network overview</h2><p>Logical relationships only, not physical wiring. Unknown Layer 2 infrastructure. Configured gateways and neighbour-cache entries do not prove current reachability.</p><ul>')
    foreach ($coverage in $Model.Coverage) { $null=$html.Append('<li>'+(& $encode ($coverage.Source+': '+$coverage.Status+' - '+$coverage.Limitation))+'</li>') }
    $null=$html.Append('</ul><p>'+(& $encode $Model.Filtering)+'</p>')
    foreach ($group in @($Model.Nodes | Where-Object { $_.Kind -ne 'NeighbourObservation' } | Group-Object InterfaceIndex)) {
        $null=$html.Append('<h3>Interface context: '+(& $encode $group.Name)+'</h3><table><tr><th>Kind</th><th>Evidence</th><th>Type / source / interval / limitation</th></tr>')
        foreach ($node in $group.Group) {
            $null=$html.Append('<tr><td>'+(& $encode $node.Kind)+'</td><td>'+(& $encode $node.Label)+'</td><td>')
            foreach ($support in $node.Support) { $null=$html.Append((& $encode ($support.EvidenceType+'; '+$support.CheckName+' '+$support.EvidenceReference+'; '+$support.StartedAt+' to '+$support.CompletedAt+'; '+$support.Limitation))) }
            $null=$html.Append('</td></tr>')
        }
        $null=$html.Append('</table>')
    }
    foreach ($group in @($Model.Nodes | Where-Object Kind -eq NeighbourObservation | Group-Object InterfaceIndex)) {
        $null=$html.Append('<details><summary>Neighbour observations on interface '+(& $encode $group.Name)+' ('+$group.Count+')</summary><table><tr><th>Address</th><th>MAC observation</th><th>State</th><th>Count eligibility</th><th>Evidence and limits</th></tr>')
        foreach ($node in $group.Group) {
            $null=$html.Append('<tr>')
            foreach ($value in @($node.Data.IPAddress,$node.Data.LinkLayerAddress,$node.Data.StateLabel,$node.Data.Eligibility,($node.Support | ConvertTo-Json -Depth 6 -Compress))) { $null=$html.Append('<td>'+(& $encode $value)+'</td>') }
            $null=$html.Append('</tr>')
        }
        $null=$html.Append('</table></details>')
    }
    $html.ToString()
}
