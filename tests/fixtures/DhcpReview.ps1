function New-DhcpReviewFixture {
    param([switch]$Current)
    $checks=@();$adapters=@();$dhcp=@();$ips=@();$metrics=@();$events=@()
    for($i=1;$i -le 12;$i++) {
        $id='11111111-1111-1111-1111-'+$i.ToString('000000000000')
        $adapters += [pscustomobject]@{InterfaceIndex=$i;InterfaceGuid=$id;Name="Synthetic <$i>";InterfaceDescription=('Synthetic description '*16);HardwareInterface=$true;Status='Disconnected';MacAddress=('02-00-00-00-00-'+$i.ToString('X2'))}
        $dhcp += [pscustomobject]@{InterfaceIndex=$i;SettingID=$id;DHCPEnabled=$true;DHCPServer='192.0.2.1';DefaultIPGateway=@($(if($Current -and $i -eq 1){'192.0.2.2'}else{'192.0.2.1'}));DNSServerSearchOrder=@('192.0.2.53');DNSDomain='example.test';DHCPLeaseObtained=$null;DHCPLeaseExpires=$null}
        $ips += [pscustomobject]@{InterfaceIndex=$i;IPAddress="192.0.2.$(20+$i)";PrefixLength=24;AddressFamily=2}
        $metrics += [pscustomobject]@{InterfaceIndex=$i;AddressFamily=2;ConnectionState=0}
        $events += [pscustomobject]@{TimeCreated='2026-01-01T08:00:00+00:00';Id=1001;ProviderName='Synthetic-DHCP';Message='Historical <DHCP> message & context.';Xml="<Event><EventData><Data Name=`"InterfaceGuid`">$id</Data></EventData></Event>"}
    }
    $dhcp[1].DHCPLeaseObtained=$(if($Current){'2026-01-01T09:00:00+00:00'}else{'2026-01-01T08:00:00+00:00'})
    $dhcp[1].DHCPLeaseExpires=$(if($Current){'2026-01-01T11:00:00+00:00'}else{'2026-01-01T10:00:00+00:00'})
    foreach($pair in @(@('Adapters',$adapters),@('DHCPAndGateways',$dhcp),@('IPAddresses',$ips),@('InterfacesAndMetrics',$metrics))) {
        $checks += [pscustomobject]@{Name=$pair[0];Status='Success';Data=@($pair[1]);StartedAt='2026-01-01T09:00:00+00:00';CompletedAt='2026-01-01T09:00:01+00:00'}
    }
    $checks += [pscustomobject]@{Name='Events:System:Network';Status='Success';Data=@([pscustomobject]@{LimitReached=$false;Events=$events})}
    [pscustomobject]@{SchemaVersion=7;Mode='Snapshot';ComputerName='SYNTHETIC';RunId=$(if($Current){'current'}else{'baseline'});StartedAt='2026-01-01T09:00:00+00:00';CompletedAt='2026-01-01T09:00:02+00:00';CollectionStatus='Complete';Checks=$checks;ContextInputs=@();Findings=Get-DiagnosticFindings $checks}
}
