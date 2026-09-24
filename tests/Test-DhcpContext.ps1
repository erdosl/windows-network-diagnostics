#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core.ps1','State.ps1','Execution.ps1','Events.ps1','Collection.ps1','Connectivity.ps1','Orchestration.ps1')){. (Join-Path $root "src\$file")}
$script:count=0
function Assert-Context {param($Condition,$Message);if(-not $Condition){throw "Assertion failed: $Message"};$script:count++}
function Copy-Context {param($Value);ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 24)}
function New-ContextFixture {
    $checks=@()
    $rows=[ordered]@{
        Adapters=@([pscustomobject]@{InterfaceIndex=7;InterfaceGuid='{11111111-1111-1111-1111-111111111111}';Name='Synthetic <wired>';InterfaceDescription='<description>';MacAddress='02-00-00-00-00-01';Status='Up';HardwareInterface=$true})
        IPAddresses=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.41';PrefixLength=24;AddressFamily=2})
        DHCPAndGateways=@([pscustomobject]@{InterfaceIndex=7;SettingID='11111111-1111-1111-1111-111111111111';DHCPEnabled=$true;DHCPServer='192.0.2.1';DefaultIPGateway=@('192.0.2.1');DNSServerSearchOrder=@('192.0.2.53','198.51.100.53');DNSDomain='example.test';DHCPLeaseObtained='2026-01-01T09:00:00+00:00';DHCPLeaseExpires='2026-01-01T11:00:00+00:00'})
        DNSServers=@([pscustomobject]@{InterfaceIndex=7;AddressFamily=2;ServerAddresses=@('192.0.2.53','198.51.100.53')})
        InterfacesAndMetrics=@([pscustomobject]@{InterfaceIndex=7;AddressFamily=2;ConnectionState=1;Dhcp=1})
        Routes=@([pscustomobject]@{InterfaceIndex=7;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.1'})
    }
    foreach($name in $rows.Keys){$checks += [pscustomobject]@{Name=$name;Status='Success';Data=$rows[$name];StartedAt='2026-01-01T10:00:00+00:00';CompletedAt='2026-01-01T10:00:01+00:00'}}
    [pscustomobject]@{SchemaVersion=6;Mode='Snapshot';ComputerName='SYNTHETIC';RunId='synthetic-baseline';StartedAt='2026-01-01T10:00:00+00:00';CompletedAt='2026-01-01T10:00:02+00:00';CollectionStatus='Complete';Checks=$checks;ContextInputs=@();Findings=Get-DiagnosticFindings $checks}
}
$workspace=Join-Path $root ('output\tests\dhcp-context-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $workspace
$e=New-ContextFixture
$baselinePath=Join-Path $workspace 'previous snapshot.json'
$e | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $baselinePath -Encoding UTF8
$baseline=Read-ContextInput $baselinePath Baseline SYNTHETIC
Assert-Context ($baseline.Interfaces.Count -eq 1) 'Schema 6 baseline supported'
$i=@(Get-DhcpInterfaceContext $e)[0]
Assert-Context ($i.StableIdentity -eq '11111111-1111-1111-1111-111111111111' -and $i.Values.SelectedDhcpServer -eq '192.0.2.1') 'Selected server and GUID retained'
Assert-Context ($i.CompetingDhcpServers -eq 'Not assessed') 'Healthy selected server never assesses competing DHCP servers'
Assert-Context ($i.Values.LeaseDurationSeconds -eq 7200 -and $i.LeaseRemainingSeconds -eq 3599) 'Lease math uses source completion'
Assert-Context ($i.Sources.DHCPAndGateways.EvidenceReferences[0] -eq '/Checks/2/Data/0') 'Source reference retained'
Assert-Context ((ConvertTo-ContextTime '/Date(0+0100)/').ToString('o') -eq '1970-01-01T01:00:00.0000000+01:00') 'Serialized epoch offset'
Assert-Context ((ConvertTo-ContextTime '20260101100000.000000+060').Offset.TotalMinutes -eq 60) 'CIM DMTF offset'
Assert-Context ($null -eq (ConvertTo-ContextTime '2026-01-01T10:00:00')) 'Offset-free dates not guessed'
Assert-Context ($null -eq (ConvertTo-ContextTime 'not a date')) 'Invalid date unknown'
$later=Copy-Context $e
$later.Checks[2].Data[0].DHCPLeaseObtained='2026-01-01T10:00:00+00:00'
$later.Checks[2].Data[0].DHCPLeaseExpires='2026-01-01T12:00:00+00:00'
$compare=Compare-DhcpContext @(Get-DhcpInterfaceContext $later) $baseline $later
Assert-Context (@($compare.Changes | Where-Object Outcome -eq 'Lease refreshed').Count -eq 2) 'Lease refreshed without claiming exchange'
Assert-Context (@($compare.Changes | Where-Object Outcome -eq 'Changed').Count -eq 0) 'Lease refresh without configuration change'
$later.Checks[0].Data[0].MacAddress='02-00-00-00-00-02'
$compare=Compare-DhcpContext @(Get-DhcpInterfaceContext $later) $baseline $later
Assert-Context (($compare.Changes | Where-Object Field -eq 'MacAddress').Outcome -eq 'Changed') 'MAC change retains stable identity match'
$later.Checks[2].Data[0].DNSServerSearchOrder=@('198.51.100.53','192.0.2.53')
$compare=Compare-DhcpContext @(Get-DhcpInterfaceContext $later) $baseline $later
Assert-Context (($compare.Changes | Where-Object Field -eq 'DnsServers').Outcome -eq 'Changed') 'DNS preference order significant'
$later.Checks[0].Status='Unavailable';$later.Checks[2].Data[0].SettingID=$null
$compare=Compare-DhcpContext @(Get-DhcpInterfaceContext $later) $baseline $later
Assert-Context (@($compare.Changes | Where-Object Outcome -eq 'Not assessed').Count -gt 0) 'No index/alias fallback on missing GUID'
$disconnected=Copy-Context $e;$disconnected.Checks[0].Data[0].Status='Disconnected'
$di=@(Get-DhcpInterfaceContext $disconnected)[0]
Assert-Context ($di.Disconnected -and $di.ConfigurationNote -match 'Retained') 'Disconnected configuration explicitly retained'
$rules=[pscustomobject]@{Version=1;Defaults=[pscustomobject]@{AllowedDhcpServers=@('198.51.100.1');AllowedGateways=@('198.51.100.1')};Interfaces=@()}
$assess=@(Test-DhcpExpectations @($i) $rules)
Assert-Context (@($assess | Where-Object Outcome -eq 'Mismatch').Count -eq 2) 'Explicit server/gateway mismatch'
Assert-Context (($assess | Where-Object Field -eq 'DnsServers').Outcome -eq 'Not assessed') 'DNS omitted remains unassessed'
Assert-Context (@(Test-DhcpExpectations @($di) $rules | Where-Object Outcome -eq 'Mismatch').Count -eq 0) 'Disconnected values not confirmed mismatch'
$rules.Defaults | Add-Member NoteProperty DnsServers @('192.0.2.53','198.51.100.53')
Assert-Context ((Test-DhcpExpectations @($i) $rules | Where-Object Field -eq 'DnsServers').Outcome -eq 'Match') 'Explicit exact ordered DNS expectation'
$rules.Interfaces=@([pscustomobject]@{InterfaceGuid=$i.StableIdentity;Rules=[pscustomobject]@{AllowedDhcpServers=@('192.0.2.1')}})
Assert-Context ((Test-DhcpExpectations @($i) $rules | Where-Object Field -eq 'AllowedDhcpServers').Outcome -eq 'Match') 'Per-field override replaces default'
$unknown=Copy-Context $e;$unknown.Checks[2].Data[0].DHCPServer='255.255.255.255'
$ui=@(Get-DhcpInterfaceContext $unknown)[0]
Assert-Context ($null -eq $ui.Values.SelectedDhcpServer -and $ui.SelectedDhcpServerRaw -eq '255.255.255.255') 'Sentinel preserved but not a usable selected server'
Assert-Context ((Test-DhcpExpectations @($ui) $rules | Where-Object Field -eq 'AllowedDhcpServers').Outcome -eq 'Not assessed') 'Sentinel not mismatch'
$unknown.Checks[2].Data[0].DHCPEnabled=$false
Assert-Context ((Test-DhcpExpectations @(Get-DhcpInterfaceContext $unknown) $rules | Where-Object Field -eq 'AllowedDhcpServers').Outcome -eq 'Not applicable') 'Disabled DHCP not applicable'
$unknown.Checks[2].Status='Unavailable'
Assert-Context ((Get-DhcpInterfaceContext $unknown).Availability.SelectedDhcpServer -eq 'Unavailable') 'Missing check does not become negative finding'
$badPath=Join-Path $workspace 'bad.json'
'{' | Set-Content $badPath
foreach($kind in @('Baseline','Expectations')) {
    $failed=Invoke-DiagnosticCheck $kind {Read-ContextInput $badPath $kind SYNTHETIC}
    Assert-Context ($failed.Status -eq 'Failed') "Malformed $kind explicitly fails"
}
$bad=Invoke-DiagnosticCheck Baseline {Read-ContextInput $baselinePath Baseline OTHER}
Assert-Context ($bad.Status -eq 'Failed') 'Other computer rejected'
$badVersion=Copy-Context $e;$badVersion.SchemaVersion=99
$badVersion | ConvertTo-Json -Depth 24 | Set-Content $badPath
Assert-Context ((Invoke-DiagnosticCheck Baseline {Read-ContextInput $badPath Baseline SYNTHETIC}).Status -eq 'Failed') 'Unsupported schema rejected'
'{"Version":1,"Defaults":{"AllowedDhcpServers":"192.0.2.1"}}' | Set-Content $badPath
Assert-Context ((Invoke-DiagnosticCheck Expectations {Read-ContextInput $badPath Expectations SYNTHETIC}).Status -eq 'Failed') 'Scalar rules rejected'
$rules | ConvertTo-Json -Depth 10 | Set-Content $badPath
Assert-Context ((Read-ContextInput $badPath Expectations SYNTHETIC).Version -eq 1) 'Valid expectations accepted'
$event=Copy-Context $e
$event.Checks[0].Data[0].MacAddress='02-00-00-00-00-02'
$event.Checks += [pscustomobject]@{Name='Events:System:Network';Status='Success';StartedAt=$event.StartedAt;CompletedAt=$event.CompletedAt;Data=@([pscustomobject]@{LimitReached=$true;Events=@([pscustomobject]@{TimeCreated='2026-01-01T09:00:00+00:00';Message='Localized <message>';Xml='<Event><EventData><Data Name="MacAddress">02-00-00-00-00-01</Data></EventData></Event>'})})}
$context=@(Get-HistoricalEventContext $event @(Get-DhcpInterfaceContext $event) $baseline)[0]
Assert-Context ($context.AgeSeconds -eq 3600 -and $context.LimitReached) 'Historical age and event limit preserved'
Assert-Context ($context.Correlations[0].NoCurrentMacMatch -and $context.Correlations[0].HistoricalMatches.Count -eq 1 -and $context.Correlations[0].HistoricalProvenance.RunId -eq 'synthetic-baseline') 'Old MAC historical correlation with provenance'
$event.Checks[-1].Data[0].Events[0].Xml='<Event><EventData><Data Name="Other">02-00-00-00-00-02</Data></EventData></Event>'
Assert-Context (@((Get-HistoricalEventContext $event @(Get-DhcpInterfaceContext $event) $baseline).Correlations).Count -eq 0) 'No sole-active-adapter or message-based attribution'
$event.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($baseline)},[pscustomobject]@{Name='Expectations';Status='Failed';Error=[pscustomobject]@{Message='<invalid expectations>'}})
$paths=Write-DiagnosticReport $event (Join-Path $workspace 'report with spaces')
$saved=Get-Content -Raw $paths.JsonPath | ConvertFrom-Json
$html=Get-Content -Raw $paths.HtmlPath
Assert-Context ($saved.Checks[-1].Data[0].Events[0].Message -eq 'Localized <message>') 'Raw event preserved'
Assert-Context ($html.Contains('&lt;wired&gt;') -and ($html.Contains('&lt;invalid expectations&gt;') -or $html.Contains('\u003cinvalid expectations\u003e')) -and -not $html.Contains('<description>') -and -not $html.Contains('<invalid expectations>')) 'New HTML fields encoded'
Assert-Context ($saved.ExpectationAssessment.Status -eq 'Failed' -and $saved.DhcpSummary.Interfaces.Count -eq 1) 'Optional failure preserves ordinary report'
# Real bounded optional-input worker; all input/output is synthetic and local.
$worker=Invoke-BoundedCheck ([pscustomobject]@{Name='Baseline';FunctionName='Read-ContextInput';Arguments=@{Path=$baselinePath;Kind='Baseline';ComputerName='SYNTHETIC'}}) (Join-Path $root src) $workspace -TimeoutSeconds 20
Assert-Context ($worker.Status -eq 'Success' -and $worker.Data[0].Interfaces.Count -eq 1) 'Optional input works in isolated PS5.1 worker'
$ambiguous=Copy-Context $e
$ambiguous.Checks[2].Data[0].SettingID='22222222-2222-2222-2222-222222222222'
$ai=@(Get-DhcpInterfaceContext $ambiguous)[0]
Assert-Context ($null -eq $ai.StableIdentity -and $ai.IdentityBasis -like 'Ambiguous*') 'Conflicting stable IDs expose ambiguity'
$duplicate=Compare-DhcpContext @($i,$i) $baseline $e
Assert-Context (@($duplicate.Changes | Where-Object Outcome -ne 'Not assessed').Count -eq 0) 'Duplicate stable GUID never selects first match'
$order=Copy-Context $e
$order.Checks[1].Data += [pscustomobject]@{InterfaceIndex=7;IPAddress='198.51.100.41';PrefixLength=24;AddressFamily=2}
$orderBaseline=[pscustomobject]@{Identity=$baseline.Identity;AdapterInventoryStatus='Success';Interfaces=@(Get-DhcpInterfaceContext $order)}
$order.Checks[1].Data=@($order.Checks[1].Data[1],$order.Checks[1].Data[0])
Assert-Context ((Compare-DhcpContext @(Get-DhcpInterfaceContext $order) $orderBaseline $order).Changes.Where({$_.Field -eq 'IPv4'}).Outcome -eq 'Unchanged') 'Address ordering alone does not change configuration'
$order.Checks[1].Status='Unavailable'
Assert-Context ((Compare-DhcpContext @(Get-DhcpInterfaceContext $order) $orderBaseline $order).Changes.Where({$_.Field -eq 'IPv4'}).Outcome -eq 'Not assessed') 'Unavailable source not address removal'
$event.Checks[-1].Data[0].Events[0].Xml='<!DOCTYPE Event [<!ENTITY external SYSTEM "file:///synthetic">]><Event>&external;</Event>'
Assert-Context ([bool](Get-HistoricalEventContext $event @(Get-DhcpInterfaceContext $event) $baseline).XmlError) 'Event XML external entities prohibited'
Assert-Context ($null -eq (ConvertTo-ContextTime '/Date(999999999999999999)/')) 'Out-of-range serialized date unknown'
$healthy=Copy-Context $e
$healthy.Checks += [pscustomobject]@{Name='Connectivity:TCP:synthetic';Status='Success';Data=@([pscustomobject]@{Outcome='Success'})}
Update-DhcpContext $healthy
Assert-Context ($healthy.DhcpSummary.CompetingDhcpServers -eq 'Not assessed' -and $healthy.Checks[-1].Data[0].Outcome -eq 'Success') 'Successful client connectivity does not assess competing servers'
$healthy.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='TimedOut';Error=[pscustomobject]@{Message='Synthetic worker timeout'}})
Update-DhcpContext $healthy
Assert-Context ($healthy.SnapshotComparison.Status -eq 'TimedOut' -and $healthy.DhcpSummary.Interfaces.Count -eq 1) 'Optional worker timeout does not remove current configuration'
$future=Copy-Context $baseline;$future.Identity.StartedAt='2026-01-02T10:00:00+00:00'
$healthy.ContextInputs=@([pscustomobject]@{Name='Baseline';Status='Success';Data=@($future)})
Update-DhcpContext $healthy
Assert-Context ($healthy.SnapshotComparison.Status -eq 'Failed') 'Future baseline not treated as previous history'
$dnsMissing=Copy-Context $e;$dnsMissing.Checks[2].Data[0].DNSServerSearchOrder=$null
Assert-Context ((Get-DhcpInterfaceContext $dnsMissing).Values.DnsServers.Count -eq 2) 'DNS inventory fallback preserves configured values'
$gatewayMissing=Copy-Context $e;$gatewayMissing.Checks[2].Data[0].DefaultIPGateway=$null
Assert-Context ((Get-DhcpInterfaceContext $gatewayMissing).GatewayValueSource -eq 'Routes') 'Configured default-route fallback labelled with source'
$event.Checks[-1].Data[0].Events[0].Xml='<Event><EventData><Data Name="HWAddress">0x020000000001</Data></EventData></Event>'
Assert-Context ((Get-HistoricalEventContext $event @(Get-DhcpInterfaceContext $event) $baseline).Correlations[0].NoCurrentMacMatch) 'DHCP HWAddress field normalized without message parsing'
$unknownLink=Copy-Context $e;$unknownLink.Checks[0].Data[0].Status=99
Assert-Context ((Get-DhcpInterfaceContext $unknownLink).Values.LinkState -eq 'Unknown (99)') 'Unknown link enum explicit and raw value retained in source'
$emptyBaseline=[pscustomobject]@{Identity=$baseline.Identity;AdapterInventoryStatus='Unavailable';Interfaces=@()}
Assert-Context ((Compare-DhcpContext @($i) $emptyBaseline $e).Changes[0].Outcome -eq 'Not assessed') 'Missing baseline inventory is not adapter appearance'
$emptyBaseline.AdapterInventoryStatus='Success'
$emptyBaseline | Add-Member NoteProperty Checks @([pscustomobject]@{Name='Adapters';Status='Success';Data=@()})
Assert-Context ((Compare-DhcpContext @($i) $emptyBaseline $e).Changes[0].Outcome -eq 'Appeared') 'Complete empty baseline establishes observed appearance'
Write-Host "PASS: $script:count DHCP context assertions on $($PSVersionTable.PSVersion)."
