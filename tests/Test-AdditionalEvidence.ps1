#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\State.ps1')
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
$work=Join-Path $root ('output\tests\additional-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$path=Join-Path $work 'incident.json'
$inputData=[pscustomobject]@{IncidentTime='2026-01-01T12:00:00+01:00';Description='<incident>';AffectedApplication='Synthetic';ConnectionInUse='Unknown';OtherDevicesAffected='unknown';FollowedEvent='wake'}
$inputData|ConvertTo-Json|Set-Content $path
$context=Read-IncidentContext $path
Assert ($context.EvidenceType -eq 'UserReported' -and -not $context.Verified) 'Incident separate from measured evidence'
$inputData.IncidentTime='2026-01-01T12:00:00';$inputData|ConvertTo-Json|Set-Content $path
Assert ((Invoke-DiagnosticCheck Incident {Read-IncidentContext $path}).Status -eq 'Failed') 'Offset required; malformed input isolated'
$inputData.IncidentTime='2026-01-01T12:00:00Z';$inputData.OtherDevicesAffected='perhaps';$inputData|ConvertTo-Json|Set-Content $path
Assert ((Invoke-DiagnosticCheck Incident {Read-IncidentContext $path}).Status -eq 'Failed') 'Tri-state validated'
Assert ((Protect-ProxyValue 'https://user:secret@proxy.invalid/pac?token=secret#part') -notmatch 'user|secret|token') 'URL credentials and token redacted'
Assert ((Protect-ProxyValue 'http=name:password@proxy.invalid:80;https=proxy.invalid:443') -notmatch 'password|name:') 'Proxy list credentials redacted'
function Get-ItemProperty {param($LiteralPath,$ErrorAction);throw [UnauthorizedAccessException]::new('Synthetic access denied')}
Assert ((Invoke-DiagnosticCheck Proxy {Get-ProxyInventory User}).Status -eq 'PermissionDenied') 'Unavailable proxy scope isolated'
Remove-Item Function:\Get-ItemProperty
$checks=@([pscustomobject]@{Name='IPAddresses';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=1;PrefixOrigin=3},[pscustomobject]@{InterfaceIndex=2;PrefixOrigin=999})},[pscustomobject]@{Name='DNSServers';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=1;DHCPEnabled=$true})})
$origins=@(Get-ConfigurationOrigins $checks)
Assert ($origins[0].Origin -eq 'DHCP' -and $origins[0].Reference -eq '/Checks/0/Data/0') 'Origin uses explicit metadata and raw reference'
Assert ($origins[1].Origin -eq 'Unknown' -and $origins[1].RawOrigin -eq 999) 'Unknown enum retained'
Assert ($origins[2].Origin -eq 'Unknown') 'DNS origin not inferred from DHCP'
$checks+=[pscustomobject]@{Name='IncidentContext';Status='Success';Data=@($context)}
$html=ConvertTo-AdditionalEvidenceHtml ([pscustomobject]@{Checks=$checks})
Assert (($html.Contains('&lt;incident&gt;') -or $html.Contains('\u003cincident\u003e')) -and -not $html.Contains('<incident>')) 'Incident HTML escaped'
Assert ((Protect-ProxyValue 'http://name:p=a;ss@proxy.invalid/') -notmatch 'name:|p=a|;ss') 'Malformed credential separators cannot leak'
Assert ((Protect-ProxyValue 'https://proxy.invalid/pac?token=first;privateSuffix') -notmatch 'first|privateSuffix') 'Semicolon query suffix fully suppressed'
Assert ((Protect-ProxyValue 'https://proxy.invalid/pac#first privateSuffix') -notmatch 'first|privateSuffix') 'Whitespace fragment suffix fully suppressed'
function Get-VpnConnection {param($AllUserConnection,$ErrorAction);[pscustomobject]@{Name='Synthetic';Guid='11111111-1111-1111-1111-111111111111';ConnectionStatus='Connected';Password='secret';EapConfigXmlStream='secret'}}
$vpn=Get-VpnInventory
Assert (-not ($vpn.PSObject.Properties.Name -contains 'Password') -and -not ($vpn.PSObject.Properties.Name -contains 'EapConfigXmlStream')) 'VPN only allowlisted fields'
Remove-Item Function:\Get-VpnConnection
$checks=@([pscustomobject]@{Name='Adapters';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=7;InterfaceGuid='11111111-1111-1111-1111-111111111111';InterfaceType=23;Status='Up'})},[pscustomobject]@{Name='Routes';Status='Success';Data=@([pscustomobject]@{InterfaceIndex=7})})
$vpnContext=@(Get-VpnInterfaceContext $checks)[0]
Assert ($vpnContext.RouteReferences[0] -eq '/Checks/1/Data/0' -and $vpnContext.VpnConnectionMapping -eq 'Unknown') 'PPP route association without invented VPN mapping'
Write-Host "PASS: $script:count additional evidence assertions on $($PSVersionTable.PSVersion)."
