#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Capture')){. (Join-Path $root "src\$file.ps1")}
Add-Type -Path (Join-Path $root 'src\CaptureDecoder.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures\CaptureFixture.cs')
$work=Join-Path $root ('output\tests\capture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$path=Join-Path $work 'synthetic.pcapng'
[NetworkDiagnostics.Tests.CaptureFixture]::Write($path)
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
$decoded=[NetworkDiagnostics.CaptureDecoder]::Decode($path,100)
Assert ($decoded.Status -eq 'Decoded' -and $decoded.Packets.Count -eq 8) 'Decode synthetic DHCP and ARP'
$packet=$decoded.Packets[0]
Assert ($packet.TransactionId -eq '00000007' -and $packet.ClientIdentifier -ne $packet.ClientHardwareAddress) 'Xid and distinct client identifiers'
Assert ($packet.Gateways[0] -eq '192.0.2.1' -and $packet.DnsServers[0] -eq '192.0.2.53') 'DHCP configured options retained'
Assert ($packet.LeaseSeconds -eq 3600 -and $packet.T1Seconds -eq 1800 -and $packet.T2Seconds -eq 3150) 'Lease T1 T2 retained'
Assert ($packet.BlockOffset -gt 0 -and $packet.Timestamp -match '\+00:00$') 'Raw packet references and timestamp'
$observations=@(Get-CaptureObservations $decoded.Packets)
$transaction=@($observations | Where-Object { $_.Kind -eq 'DhcpTransaction' -and $_.ClientIdentifier -eq '010A' })[0]
Assert ($transaction.ObservedCompetingResponders -and $transaction.OfferResponders.Count -eq 2) 'Multiple observed responders'
Assert ($transaction.SelectedServerIdentifiers[0] -eq '192.0.2.2') 'REQUEST selects server, not first offer'
Assert ($transaction.AckNakConflict -and $transaction.AppliedConfiguration -eq 'Not assessed') 'Conflicting ACK NAK not applied configuration'
Assert (@($observations | Where-Object Kind -eq 'DhcpTransaction').Count -eq 2) 'Distinct clients sharing a hostname not merged'
$arp=@($observations | Where-Object Kind -eq 'ArpClaims')[0]
Assert ($arp.HardwareAddresses.Count -eq 2 -and $arp.Fault -eq 'Not assessed') 'ARP claims not fault diagnosis'
$limit=[NetworkDiagnostics.CaptureDecoder]::Decode($path,1)
Assert ($limit.PacketLimitReached) 'Decoder packet budget enforced'
$bytes=[IO.File]::ReadAllBytes($path);[IO.File]::WriteAllBytes((Join-Path $work 'truncated.pcapng'),$bytes[0..($bytes.Length-3)])
$bad=[NetworkDiagnostics.CaptureDecoder]::Decode((Join-Path $work 'truncated.pcapng'),100)
Assert ($bad.Status -eq 'PartialOrUnsupported' -and $bad.Errors.Count -eq 1) 'Malformed/truncated input explicit'
function New-SnapshotIdentity {[pscustomobject]@{ComputerName='SYNTHETIC';RunId=[guid]::NewGuid().ToString();CollectorVersion='0.5.0';IsElevated=$false;StartedAt=[DateTimeOffset]::Now.ToString('o')}}
foreach($reason in @('ToolMissing','ExistingSession','TimedOut','UnsupportedVersion','PermissionDenied','SessionOwnershipNotGuaranteed')){
    $result=Invoke-CaptureRequest -RepositoryRoot $root -AdapterGuid '11111111-1111-1111-1111-111111111111' -DurationSeconds 5 -MaxSizeMB 1 -TestOutputRoot $work -CapabilityReader { [pscustomobject]@{Status='Unavailable';ReasonCode=$reason} }
    Assert ($result.Evidence.CollectionStatus -eq 'Unavailable' -and $result.Evidence.EffectiveFilters.Count -eq 0 -and $result.Evidence.SessionOwnership -eq 'No session started') "No mutation on $reason"
}
$rejected=$false;try{Invoke-CaptureRequest -RepositoryRoot $root -AdapterGuid '11111111-1111-1111-1111-111111111111' -MaxSizeMB 0}catch{$rejected=$true}
Assert ($result.Evidence.RequestedFilters.Count -eq 1 -and $result.Evidence.RequestedFilters[0] -eq 'IPv4 UDP ports 67/68') 'Disabled ARP adds no null filter'
Assert $rejected 'Size limit validated before any operation'
$script:saved=@{}
function Set-AtomicText {param($Path,$Text);$script:saved[$Path]=$Text}
$report=Join-Path $work 'model-import'
$import=Import-CaptureEvidence $path $report
Assert ($import.DecoderStatus -eq 'Decoded' -and $import.Artifact.Sha256 -and $import.Artifact.Path -eq 'capture.pcapng') 'Artifact integrity and safe reference'
$html=$script:saved[(Join-Path $report 'summary.html')]
Assert (-not $html.Contains('<test>') -and ($html.Contains('&lt;test&gt;') -or $html.Contains('\u003ctest\u003e'))) 'Decoded strings HTML escaped'
$rawBefore=(Get-FileHash $path).Hash
$badImport=Import-CaptureEvidence (Join-Path $work 'truncated.pcapng') (Join-Path $work 'bad-model-import')
Assert ($badImport.DecoderStatus -eq 'PartialOrUnsupported' -and (Test-Path (Join-Path $work 'bad-model-import\capture.pcapng'))) 'Decode failure retains raw bytes with mocked report persistence'
Assert ((Get-FileHash $path).Hash -eq $rawBefore) 'Input artifact unchanged'
Write-Host "PASS: $script:count capture evidence assertions; synthetic bytes and mocked capability refusal, no live capture."
