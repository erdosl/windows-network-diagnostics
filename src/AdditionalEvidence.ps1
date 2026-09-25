function Read-IncidentContext {
    param([string]$Path)
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($item.PSIsContainer -or $item.Length -gt 32768){throw 'Incident input must be a JSON file of at most 32 KiB.'}
    $inputObject=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($null -eq $inputObject -or $inputObject -is [array]){throw 'Incident input must be one JSON object.'}
    $allowed=@('IncidentTime','Description','AffectedApplication','ConnectionInUse','OtherDevicesAffected','FollowedEvent')
    foreach($p in $inputObject.PSObject.Properties){
        if($p.Name -notin $allowed -or $p.Value -isnot [string] -or $p.Value.Length -gt 2048){throw 'Unknown field, non-string value, or incident field longer than 2048 characters.'}
    }
    $time=[DateTimeOffset]::MinValue
    if($inputObject.IncidentTime -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' -or -not [DateTimeOffset]::TryParse($inputObject.IncidentTime,[ref]$time)){throw 'IncidentTime requires an ISO timestamp with timezone offset.'}
    if([string]::IsNullOrWhiteSpace($inputObject.Description) -or $inputObject.OtherDevicesAffected -cnotin @('yes','no','unknown')){throw 'Description and OtherDevicesAffected (yes/no/unknown) are required.'}
    [pscustomobject]@{EvidenceType='UserReported';Verified=$false;Context=$inputObject;Limitation='User recollection, not measured evidence or a verified cause. Do not include credentials.'}
}

function Protect-ProxyValue {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrEmpty($Value)){return $null}
    # Never retain userinfo, URL queries/fragments (often tokens), or malformed
    # credential-like strings. Works for semicolon-delimited WinINet proxy lists.
    if($Value.Contains('@')){return '[redacted: credential-like proxy value]'}
    # Semicolons/whitespace can belong to a URL token, not just a proxy list.
    # Suppress the entire ambiguous value rather than leaking a token suffix.
    if($Value.IndexOfAny([char[]]'?#') -ge 0){return '[redacted: proxy URL query or fragment]'}
    $Value
}

function Get-ProxyInventory {
    param([ValidateSet('User','Machine')][string]$Scope)
    $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if($Scope -eq 'Machine'){$path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'}
    try{$settings=Get-ItemProperty -LiteralPath $path -ErrorAction Stop}
    catch{
        if($_.Exception -is [Management.Automation.ItemNotFoundException]){throw [NotSupportedException]::new('Proxy settings source is unavailable for this scope.', $_.Exception)}
        throw
    }
    [pscustomobject]@{Scope=$Scope;AccountScope=$(if($Scope -eq 'User'){'Collector process current user; may differ from affected application'}else{'Machine WinINet settings; not a complete WinHTTP/application proxy policy'})
        ProxyEnable=$settings.ProxyEnable;ProxyServer=Protect-ProxyValue $settings.ProxyServer;AutoConfigURL=Protect-ProxyValue $settings.AutoConfigURL
        ProxyOverride=Protect-ProxyValue $settings.ProxyOverride;AutoDetect=$settings.AutoDetect
        Limitation='Only allowlisted registry values; missing values are unknown. PAC is never fetched. Credentials/query/fragment redacted; applications may use other policies.'}
}

function Get-WinHttpProxyInventory {
    if(-not ('NetworkDiagnostics.NativeInventory' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'NativeInventory.cs')}
    $settings=[NetworkDiagnostics.NativeInventory]::DefaultProxy()
    [pscustomobject]@{Scope='Machine WinHTTP default';AccessType=$settings[0];Proxy=Protect-ProxyValue $settings[1];Bypass=Protect-ProxyValue $settings[2];Limitation='Default configuration only; application/session and automatic proxy decisions not assessed. No PAC fetch.'}
}

function Get-VpnInterfaceContext {
    param($Checks)
    # PPP/tunnel types are candidates, not proof of VPN purpose; do not guess from names.
    $adapters=@($Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object {$_.Data})
    foreach($adapter in @($adapters | Where-Object { [string]$_.InterfaceType -in @('23','131','Ppp','Tunnel') })){
        $routes=@();for($i=0;$i -lt @($Checks).Count;$i++){
            if($Checks[$i].Name -ne 'Routes' -or $Checks[$i].Status -ne 'Success'){continue}
            for($j=0;$j -lt @($Checks[$i].Data).Count;$j++){if($Checks[$i].Data[$j].InterfaceIndex -eq $adapter.InterfaceIndex){$routes+="/Checks/$i/Data/$j"}}
        }
        [pscustomobject]@{InterfaceIndex=$adapter.InterfaceIndex;InterfaceGuid=$adapter.InterfaceGuid;State=$adapter.Status;InterfaceType=$adapter.InterfaceType
            RouteReferences=$routes;VpnConnectionMapping='Unknown';Limitation='PPP/tunnel interface candidate; type alone does not establish VPN purpose. VPN profile GUID is not treated as adapter GUID. Third-party VPN APIs not queried.'}
    }
}

function Get-VpnInventory {
    param([bool]$AllUsers=$false)
    # Never serialize full VPN profiles (EAP, credentials, certificates etc.).
    Get-VpnConnection -AllUserConnection:$AllUsers -ErrorAction Stop | Where-Object ConnectionStatus -eq 'Connected' |
        Select-Object Name,Guid,ConnectionStatus,TunnelType,SplitTunneling,@{n='Scope';e={if($AllUsers){'AllUsers'}else{'CurrentUser'}}}
}

function Get-BindingInventory {
    Get-NetAdapterBinding -Name '*' -IncludeHidden -AllBindings -ErrorAction Stop | Where-Object Enabled |
        Select-Object Name,InterfaceDescription,DisplayName,ComponentID,Enabled
}

function Get-ConfigurationOrigins {
    param($Checks)
    for($ci=0;$ci -lt @($Checks).Count;$ci++){
        $check=$Checks[$ci]
        if($check.Name -notin @('IPAddresses','Routes','DNSServers')){continue}
        if($check.Status -ne 'Success'){
            [pscustomobject]@{Kind=$check.Name;Origin='Unknown';SourceStatus=$check.Status;Reference="/Checks/$ci"};continue
        }
        for($di=0;$di -lt @($check.Data).Count;$di++){
            $row=$check.Data[$di];$origin='Unknown';$reason='No authoritative origin metadata for this value.';$raw=$null
            if($check.Name -eq 'IPAddresses'){
                $raw=$row.PrefixOrigin
                if([string]$raw -in @('Dhcp','3')){$origin='DHCP';$reason='Address PrefixOrigin reports DHCP.'}
                elseif([string]$raw -in @('Manual','1')){$origin='Manual';$reason='Address PrefixOrigin reports manual configuration.'}
            }elseif($check.Name -eq 'Routes'){
                $raw=$row.Protocol
                if([string]$raw -in @('Dhcp','19')){$origin='DHCP';$reason='Route protocol reports DHCP.'}
                # NetMgmt can represent management software, not necessarily a human.
            }else{$reason='DNS server API does not establish DHCP/manual origin; DHCP enabled is not sufficient.'}
            [pscustomobject]@{Kind=$check.Name;InterfaceIndex=$row.InterfaceIndex;Origin=$origin;Reason=$reason;RawOrigin=$raw;SourceStatus='Success';Reference="/Checks/$ci/Data/$di"}
        }
    }
}

function ConvertTo-AdditionalEvidenceHtml {
    param($Evidence)
    $incident=@($Evidence.Checks | Where-Object Name -eq 'IncidentContext')
    $origins=@($Evidence.ConfigurationOrigins)
    $inventory=@($Evidence.Checks | Where-Object Name -in @('Proxy:User','Proxy:Machine','Proxy:WinHTTP','VPN:User','VPN:AllUsers','AdapterBindings'))
    $html='<h2>Incident and configuration context</h2><p>User reports are unverified. Installed bindings and VPN/proxy settings do not establish fault.</p>'
    foreach($analysis in @($Evidence.Analysis.Sections | Where-Object { $_.Section -in @('ConfigurationOrigins','VpnInterfaceContext') -and $_.Status -ne 'Complete' })){
        $html+='<p>'+[Net.WebUtility]::HtmlEncode($analysis.Section+': '+$analysis.Status+'; '+$analysis.Error.Message)+'</p>'
    }
    foreach($section in @(@('User-reported incident',$incident),@('Configuration origins',$origins),@('VPN, proxy and bindings',$inventory),@('PPP/tunnel interface route associations',@($Evidence.VpnInterfaceContext)))){
        $html+='<details><summary>'+[Net.WebUtility]::HtmlEncode($section[0])+'</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json -InputObject $section[1] -Depth 16))+'</pre></details>'
    }
    $html
}
