function Get-NativeCaptureCapability {
    # Read-only help inspection. Never run status/stop/start/filter mutation here.
    $tool=Get-Command pktmon.exe -ErrorAction SilentlyContinue
    if(-not $tool){return [pscustomobject]@{Status='Unavailable';ReasonCode='ToolMissing';Tool='pktmon';Version=$null;OwnerScopedStop=$false}}
    $start=(& $tool.Source start help 2>&1) -join "`n"
    $filter=(& $tool.Source filter add help 2>&1) -join "`n"
    if(-not ('NetworkDiagnostics.NativeInventory' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'NativeInventory.cs')}
    $sessionApi=[NetworkDiagnostics.NativeInventory]::HasCaptureSessionApi()
    [pscustomobject]@{Status='Unavailable';ReasonCode='SessionOwnershipNotGuaranteed';Tool='pktmon';Version=(Get-Item $tool.Source).VersionInfo.FileVersion
        ComponentSelection=($start -match '--comp');NarrowFilters=($filter -match '--port' -and $filter -match '--ethertype');OwnerScopedStop=$false;IndependentSessionApiExports=$sessionApi
        Explanation='The supported pktmon CLI has global filters and no owner-scoped conditional stop. A preflight status check cannot prevent a competing session race. No capture/filter command is issued.'}
}

function Get-CaptureObservations {
    param($Packets)
    foreach($group in @($Packets | Where-Object Kind -eq 'DHCPv4' | Group-Object { [string]$_.SectionId+'|'+$_.InterfaceId+'|'+$_.TransactionId+'|'+$_.ClientHardwareType+'|'+$_.ClientHardwareAddress+'|'+$_.ClientIdentifier })){
        $rows=@($group.Group);$offers=@($rows | Where-Object MessageType -eq 2)
        $responders=@($offers | ForEach-Object {$_.ServerIdentifier+'|'+$_.PacketSource} | Sort-Object -Unique)
        [pscustomobject]@{Kind='DhcpTransaction';SectionId=$rows[0].SectionId;InterfaceId=$rows[0].InterfaceId;TransactionId=$rows[0].TransactionId;ClientHardwareAddress=$rows[0].ClientHardwareAddress;ClientIdentifier=$rows[0].ClientIdentifier
            OfferResponders=$responders;ObservedCompetingResponders=($responders.Count -gt 1)
            SelectedServerIdentifiers=@($rows | Where-Object { $_.MessageType -eq 3 -and $_.ServerIdentifier } | ForEach-Object {$_.ServerIdentifier})
            AckNakConflict=(@($rows | Where-Object MessageType -eq 5).Count -gt 0 -and @($rows | Where-Object MessageType -eq 6).Count -gt 0)
            PacketReferences=@($rows | ForEach-Object {$_.BlockOffset});AppliedConfiguration='Not assessed'
            Limitation='Exchange may be incomplete. Client-ID presence differences remain separate. REQUEST Server-ID records selection, not first-offer ordering. ACK does not establish applied options. One responder does not establish exclusivity.'}
    }
    foreach($group in @($Packets | Where-Object {$_.Kind -eq 'ARP' -and $_.Operation -in @(1,2) -and $_.SenderProtocolAddress -ne '0.0.0.0'} | Group-Object {[string]$_.SectionId+'|'+$_.InterfaceId+'|'+$_.SenderProtocolAddress})){
        $claims=@($group.Group.SenderHardwareAddress | Sort-Object -Unique)
        if($claims.Count -gt 1){[pscustomobject]@{Kind='ArpClaims';SectionId=$group.Group[0].SectionId;InterfaceId=$group.Group[0].InterfaceId;IPAddress=$group.Group[0].SenderProtocolAddress;HardwareAddresses=$claims;PacketReferences=@($group.Group.BlockOffset);Observation='Differing sender MAC claims for one observed IP on one capture interface; relevance and cause require interpretation.';Fault='Not assessed';Role='Unknown; not equated with local adapter or gateway identity'}}
    }
}

function Import-CaptureEvidence {
    param([string]$Path,[string]$OutputDirectory,[ValidateRange(1,10000)][int]$MaxPackets=10000)
    $null=New-Item -ItemType Directory -Path $OutputDirectory -Force
    $raw=Join-Path $OutputDirectory 'capture.pcapng'
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($item.Length -gt 64MB){throw 'Capture input exceeds 64 MiB.'}
    # Preserve raw input first; decoding failure must never discard it.
    Copy-Item -LiteralPath $Path -Destination $raw -ErrorAction Stop
    $evidence=[pscustomobject]@{SchemaVersion=9;Mode='OfflineCaptureAnalysis';RunId=[guid]::NewGuid().ToString();StartedAt=[DateTimeOffset]::Now.ToString('o');CompletedAt=$null
        Artifact=[pscustomobject]@{Path='capture.pcapng';Length=(Get-Item $raw).Length;Sha256=(Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash}
        DecoderStatus='Incomplete';Decoded=$null;Observations=@();Error=$null;NeighbourEvidence='Not collected; offline artifact cannot establish contemporaneous neighbour state.'}
    Set-AtomicText (Join-Path $OutputDirectory 'evidence.json') (ConvertTo-Json $evidence -Depth 24)
    try{
        if(-not ('NetworkDiagnostics.CaptureDecoder' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'CaptureDecoder.cs')}
        $evidence.Decoded=[NetworkDiagnostics.CaptureDecoder]::Decode($raw,$MaxPackets)
        $evidence.DecoderStatus=$evidence.Decoded.Status
        $evidence.Observations=@(Get-CaptureObservations $evidence.Decoded.Packets)
    }catch{$evidence.DecoderStatus='Failed';$evidence.Error=$_.Exception.Message}
    $evidence.CompletedAt=[DateTimeOffset]::Now.ToString('o')
    Set-AtomicText (Join-Path $OutputDirectory 'evidence.json') (ConvertTo-Json $evidence -Depth 24)
    $html='<html><meta charset="utf-8"><h1>Offline DHCP/ARP observations</h1><p>Local sensitive capture. No physical topology or network fault inferred.</p><a href="capture.pcapng">Raw capture</a><details><summary>Evidence, coverage and observations</summary><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $evidence -Depth 24))+'</pre></details></html>'
    Set-AtomicText (Join-Path $OutputDirectory 'summary.html') $html
    $evidence
}

function Invoke-CaptureRequest {
    param([string]$RepositoryRoot,[Parameter(Mandatory)][guid[]]$AdapterGuid,
        [ValidateRange(5,300)][int]$DurationSeconds=30,[ValidateRange(1,64)][int]$MaxSizeMB=16,[switch]$IncludeArp,
        [scriptblock]$CapabilityReader,[string]$TestOutputRoot)
    $identity=New-SnapshotIdentity
    $root=Join-Path $RepositoryRoot 'output';if($TestOutputRoot){$root=$TestOutputRoot}
    $directory=Join-Path $root ('capture-'+($identity.ComputerName -replace '[^A-Za-z0-9_.-]','_')+'-'+$identity.RunId)
    $null=New-Item -ItemType Directory -Path $directory
    if($CapabilityReader){$capability=& $CapabilityReader}
    else{
        $check=Invoke-BoundedCheck ([pscustomobject]@{Name='CaptureCapability';FunctionName='Get-NativeCaptureCapability';Arguments=@{}}) (Join-Path $RepositoryRoot 'src') $directory 10 -AdditionalSources @((Join-Path $RepositoryRoot 'src\Capture.ps1'))
        $capability=[pscustomobject]@{Status=$check.Status;Data=$check.Data;Error=$check.Error}
    }
    # No native backend with verified ownership is implemented. Never turn a mocked
    # capability flag into permission to execute global start/stop/filter commands.
    $requestedFilters=@('IPv4 UDP ports 67/68');if($IncludeArp){$requestedFilters+='ARP'}
    $result=[pscustomobject]@{SchemaVersion=9;Mode='CaptureRequest';Identity=$identity;CollectionStatus='Unavailable';StartedAt=$identity.StartedAt;CompletedAt=[DateTimeOffset]::Now.ToString('o')
        RequestedAdapters=@($AdapterGuid | ForEach-Object {$_.ToString('D')});EffectiveAdapters=@();RequestedFilters=$requestedFilters;EffectiveFilters=@()
        DurationSeconds=$DurationSeconds;MaxSizeMB=$MaxSizeMB;Capability=$capability;SessionOwnership='No session started';Cleanup='Not required: no session/filter mutation'
        ReasonCode='NoSafeNativeBackend';PacketDrops=$null;Truncation=$null
        Explanation='Capture refused: supported CLI cannot guarantee both narrow DHCP filtering and session ownership. Elevation alone cannot resolve this. No existing session is queried, changed or stopped.'
        Limitation='Windows vantage may miss other clients unicast traffic. Drop/truncation and decoding support are not inferred from tool availability.'}
    Set-AtomicText (Join-Path $directory 'evidence.json') (ConvertTo-Json $result -Depth 16)
    Set-AtomicText (Join-Path $directory 'summary.html') ('<html><meta charset="utf-8"><h1>Capture unavailable</h1><pre>'+[Net.WebUtility]::HtmlEncode((ConvertTo-Json $result -Depth 16))+'</pre></html>')
    [pscustomobject]@{Directory=$directory;Evidence=$result}
}
