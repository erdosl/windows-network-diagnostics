#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
$count=0
function Assert-Presentation { param($Condition,$Message); if (-not $Condition) { throw $Message }; $script:count++ }
foreach ($pair in @(@(2,'IPv4'),@(23,'IPv6'),@('InterNetworkV6','IPv6'),@(999,'Unknown (999)'),@($null,'Unknown (missing)'))) {
    Assert-Presentation ((Get-NetworkDisplayLabel AddressFamily $pair[0]) -eq $pair[1]) 'Address family label'
}
foreach ($pair in @(@(0,'Disconnected'),@(1,'Connected'),@('Connected','Connected'),@(42,'Unknown (42)'),@($null,'Unknown (missing)'))) {
    Assert-Presentation ((Get-NetworkDisplayLabel ConnectionState $pair[0]) -eq $pair[1]) 'Connection state label'
}
$target=[pscustomobject]@{TargetId='synthetic';Server='2001:db8:1234:5678:abcd:abcd:abcd:abcd%77';Reason='Legacy DNS discovery address; operational use unconfirmed.';ConfiguredAssociations=@([pscustomobject]@{InterfaceIndex=77;InterfaceAlias='Synthetic alias';Adapters=@();IPInterfaceStates=@([pscustomobject]@{AddressFamily=23;ConnectionState=0},[pscustomobject]@{AddressFamily=999;ConnectionState=42})})}
$checks = foreach ($type in @('A','AAAA')) { [pscustomobject]@{Name="Connectivity:DNS:test:$type";Status='Skipped';Request=@{Kind='DNS';DnsTarget=$target};Data=@([pscustomobject]@{Kind='DNS';DnsTarget=$target;Outcome='Skipped';SkipReason=$target.Reason;Evidence=@{QueryType=$type;QueryName='synthetic.invalid'}})} }
$before=ConvertTo-Json $checks -Depth 16
foreach ($width in @(20,40,60,80,120)) {
    $lines=@(Format-DnsConsoleReport $checks -Width $width)
    Assert-Presentation (@($lines | Where-Object Length -gt $width).Count -eq 0) "No overflow at $width"
    $flat=($lines -join '') -replace '\s',''
    $reasonText=$flat
    if ($width -ge 60) {
        $reasonStart=[int](($width-6)*.32)+5+9+6
        $reasonText=(($lines | Where-Object { $_.Length -gt $reasonStart } | ForEach-Object { $_.Substring($reasonStart) }) -join '') -replace '\s',''
    }
    Assert-Presentation ($flat.Contains(($target.Server -replace '\s','')) -and $flat.Contains('Skipped') -and $flat.Contains('AAAA') -and $reasonText.Contains('operationaluseunconfirmed.')) "Essential values retained at $width"
    Assert-Presentation (([regex]::Matches($flat,'Syntheticalias')).Count -eq 1) "Association once at $width"
    Assert-Presentation ($flat.Contains('IPv6/Disconnected') -and $flat.Contains('Unknown(999)/Unknown(42)')) "Readable and unknown states at $width"
}
Assert-Presentation ((ConvertTo-Json $checks -Depth 16) -eq $before) 'Raw evidence unchanged'
$failure=[pscustomobject]@{Name='Connectivity:DNS:failed';Status='Success';Error=$null;Request=@{Kind='DNS';Destination='192.0.2.53';QueryType='A'};Data=@([pscustomobject]@{Kind='DNS';Outcome='Failed';DnsError=@{Classification='Refused';Code=9005;Message='Synthetic refusal'}})}
Assert-Presentation (((Format-DnsConsoleReport @($failure) -Width 80) -join '') -match 'Refused') 'DNS error reason shown'
$failure.Status='TimedOut';$failure.Data=@();$failure.Error=@{Message='Worker terminated'}
Assert-Presentation ((((Format-DnsConsoleReport @($failure) -Width 80) -join '') -replace '\s','') -match 'Workerterminated') 'Worker failure reason shown without invented network outcome'
Write-Host "PASS: $count presentation assertions."
