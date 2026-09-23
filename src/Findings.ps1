function Get-AddressEvidenceLabel {
    param([string]$Field,$Value)
    $map=switch($Field) {
        'AddressState' { @{ '0'='Invalid';'1'='Tentative';'2'='Duplicate';'3'='Deprecated';'4'='Preferred' } }
        'PrefixOrigin' { @{ '0'='Other';'1'='Manual';'2'='WellKnown';'3'='Dhcp';'4'='RouterAdvertisement' } }
        'SuffixOrigin' { @{ '0'='Other';'1'='Manual';'2'='WellKnown';'3'='Dhcp';'4'='Link';'5'='Random' } }
    }
    if($null -eq $Value -or [string]$Value -eq ''){return 'Unknown (missing)'}
    if($map.ContainsKey([string]$Value)){return $map[[string]$Value]}
    if([string]$Value -in $map.Values){return [string]$Value}
    'Unknown ('+[string]$Value+')'
}

function Get-ApipaContext {
    param([object[]]$Checks)
    $items=@()
    for($ci=0;$ci -lt $Checks.Count;$ci++) {
        $check=$Checks[$ci]
        if($check.Name -ne 'IPAddresses' -or $check.Status -ne 'Success'){continue}
        for($di=0;$di -lt @($check.Data).Count;$di++) {
            $address=@($check.Data)[$di]
            if((Get-AddressClassification $address.IPAddress) -ne 'APIPA'){continue}
            $sources=[ordered]@{}; $data=@{}; $refs=@("/Checks/$ci/Data/$di")
            foreach($name in @('Adapters','InterfacesAndMetrics','Routes','DHCPAndGateways')) {
                $records=@()
                for($si=0;$si -lt $Checks.Count;$si++) {
                    if($Checks[$si].Name -ne $name){continue}
                    $sources[$name]=$Checks[$si].Status
                    if($Checks[$si].Status -ne 'Success'){continue}
                    for($ri=0;$ri -lt @($Checks[$si].Data).Count;$ri++) {
                        $record=@($Checks[$si].Data)[$ri]
                        if($record.InterfaceIndex -eq $address.InterfaceIndex) { $records += $record; $refs += "/Checks/$si/Data/$ri" }
                    }
                }
                if(-not $sources.Contains($name)){$sources[$name]='NotCollected'}
                elseif($sources[$name] -eq 'Success' -and -not $records.Count -and $name -ne 'Routes'){$sources[$name]='No matching interface record'}
                $data[$name]=$records
            }
            $adapters=@($data.Adapters)
            $kind='Unknown'
            if($adapters.Count -eq 1 -and $adapters[0].HardwareInterface -is [bool]){$kind=$(if($adapters[0].HardwareInterface -eq $true){'Physical'}else{'Virtual/software'})}
            $link=@($adapters | ForEach-Object { if([string]$_.Status -in @('Up','Down','Disconnected','Disabled','Not Present','Unknown')){[string]$_.Status}else{'Unknown ('+[string]$_.Status+')'} }) -join ', '
            if(-not $link){$link='Unknown (missing)'}
            $ipInterfaces=@($data.InterfacesAndMetrics | Where-Object { [string]$_.AddressFamily -in @('2','IPv4','InterNetwork') })
            $connection=@($ipInterfaces | ForEach-Object {Get-NetworkDisplayLabel ConnectionState $_.ConnectionState}) -join ', '
            if(-not $connection){$connection='Unknown (missing IPv4 state)'}
            $disconnected=($link -in @('Down','Disconnected','Disabled','Not Present') -or $connection -eq 'Disconnected')
            $active=($link -eq 'Up' -and -not $disconnected)
            $default=$(if($sources.Routes -ne 'Success'){'Unknown'}elseif(@($data.Routes | Where-Object DestinationPrefix -in @('0.0.0.0/0','::/0')).Count){'Yes (configured only)'}else{'No'})
            $aliases=@(@($address.InterfaceAlias)+@($adapters | ForEach-Object Name) | Where-Object {$_} | Select-Object -Unique) -join ', '
            $description=@($adapters | ForEach-Object InterfaceDescription) -join ', '
            $missing=@($sources.Keys | Where-Object {$sources[$_] -ne 'Success'} | ForEach-Object {$_+': '+$sources[$_]})
            $origin='PrefixOrigin='+(Get-AddressEvidenceLabel PrefixOrigin $address.PrefixOrigin)+'; SuffixOrigin='+(Get-AddressEvidenceLabel SuffixOrigin $address.SuffixOrigin)
            $observation="APIPA address $($address.IPAddress) on interface $($address.InterfaceIndex) ($aliases); description: $description; $kind; link: $link; IPv4 connection: $connection; address state: $(Get-AddressEvidenceLabel AddressState $address.AddressState); $origin; default route: $default."
            if($missing.Count){$observation += ' Missing sources: '+($missing -join '; ')+'.'}
            if($disconnected){$observation += ' Retained address configuration on a disconnected interface does not establish a current internet-path fault.'}
            $auto=([string]$address.PrefixOrigin -in @('3','Dhcp') -or [string]$address.SuffixOrigin -in @('3','Dhcp','4','Link','5','Random'))
            $dhcp=(@($data.DHCPAndGateways | Where-Object DHCPEnabled -eq $true).Count -gt 0 -or @($ipInterfaces | Where-Object {[string]$_.Dhcp -in @('1','Enabled')}).Count -gt 0)
            $hypothesis=$(if($auto -and $dhcp){'Automatic address origin and enabled DHCP make failure to obtain a usable lease one possibility; this is not a proven cause.'}else{'APIPA requires interface and configuration context; its presence does not establish DHCP failure or an internet-path fault.'})
            if($kind -eq 'Virtual/software'){$hypothesis += ' Virtual/software status alone does not establish that APIPA is harmless.'}
            $items += [pscustomobject]@{IPAddress=$address.IPAddress;InterfaceIndex=$address.InterfaceIndex;Aliases=$aliases;Description=$description;Kind=$kind;LinkState=$link;ConnectionState=$connection
                AddressStateRaw=$address.AddressState;PrefixOriginRaw=$address.PrefixOrigin;SuffixOriginRaw=$address.SuffixOrigin;DefaultRouteConfigured=$default
                AdapterEvidence=$adapters;IPInterfaceEvidence=$ipInterfaces;SourceStatus=[pscustomobject]$sources;EvidenceReferences=$refs;StartedAt=$check.StartedAt;CompletedAt=$check.CompletedAt
                Priority=$(if($active -and $kind -eq 'Physical'){0}elseif($disconnected){2}else{1});Observation=$observation;Hypothesis=$hypothesis}
        }
    }
    $items | Sort-Object Priority,InterfaceIndex,IPAddress
}
