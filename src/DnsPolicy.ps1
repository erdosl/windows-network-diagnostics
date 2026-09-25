# Passive local DNS policy inventory; no resolver query or remote session.
function Get-EffectiveDnsPolicy {
    $fields=@('Namespace','NameServers','QueryPolicy','SecureNameQueryFallback','NameEncoding','DirectAccessEnabled','DirectAccessDnsServers','DirectAccessProxyType','DirectAccessProxyName','DirectAccessQueryIPsecEncryption','DirectAccessQueryIPsecRequired','DnsSecQueryIPsecEncryption','DnsSecQueryIPsecRequired','DnsSecValidationRequired')
    $rows=@(Get-DnsClientNrptPolicy -Effective -ErrorAction Stop)
    $policies=@(foreach($row in $rows){
        $values=[ordered]@{};$missing=@()
        foreach($field in $fields){if($row.PSObject.Properties[$field]){$values[$field]=$row.$field}else{$missing+=$field}}
        [pscustomobject]@{Settings=[pscustomobject]$values;MissingFields=$missing}
    })
    [pscustomobject]@{ContractVersion=1;Provenance='Local Get-DnsClientNrptPolicy -Effective';PolicyState=$(if($rows.Count){'Populated'}else{'ObservedEmpty'});Policies=$policies;Limitation='Effective policy may affect resolution; it does not establish the resolver used by an application. No DNS query was sent.'}
}

function Get-GlobalDnsSettings {
    $rows=@(Get-DnsClientGlobalSetting -ErrorAction Stop)
    foreach($row in $rows){
        $values=[ordered]@{};$missing=@()
        foreach($field in @('SuffixSearchList','UseDevolution','DevolutionLevel')){if($row.PSObject.Properties[$field]){$values[$field]=$row.$field}else{$missing+=$field}}
        [pscustomobject]@{ContractVersion=1;Provenance='Local Get-DnsClientGlobalSetting';Settings=[pscustomobject]$values;MissingFields=$missing;Limitation='Global client configuration, not a per-application resolver observation.'}
    }
    if(-not $rows.Count){throw [IO.InvalidDataException]::new('Global DNS settings returned no object; settings are unavailable.')}
}

function ConvertTo-DnsPolicyHtml {
    param($Evidence)
    $html='<h3>Effective DNS policy and global settings</h3><p>Local policy can affect name resolution. These settings do not prove which resolver an application used.</p>'
    for($i=0;$i -lt $Evidence.Checks.Count;$i++){
        $check=$Evidence.Checks[$i];if($check.Name -notin @('DNS:EffectivePolicy','DNS:GlobalSettings')){continue}
        $html+='<p>'+[Net.WebUtility]::HtmlEncode($check.Name+': '+$check.Status)+' '+(ConvertTo-ContextLink ([pscustomobject]@{Path="/Checks/$i"}) 'Policy/settings evidence')+'</p>'
        if($check.Name -eq 'DNS:EffectivePolicy' -and $check.Status -eq 'Success'){$html+='<p>'+[Net.WebUtility]::HtmlEncode($check.Data[0].PolicyState)+'</p>'}
    }
    $html
}
