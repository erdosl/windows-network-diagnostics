#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core.ps1','State.ps1','Collection.ps1')){. (Join-Path $root "src\$file")}
$script:count=0
function Assert-Fix {param($Condition,$Message);if(-not $Condition){throw $Message};$script:count++}
$script:mode='ok'
function Get-NetAdapterStatistics {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    Assert-Fix ($Name -eq '*' -and $IncludeHidden) 'Hidden provider inventory queried without interpreting alias wildcards'
    switch($script:mode){
        'missing' {$PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([Exception]::new('Original localized message'),'CmdletizationQuery_NotFound_Name',[Management.Automation.ErrorCategory]::ObjectNotFound,$Name))}
        'denied' {throw [UnauthorizedAccessException]::new('Synthetic denied')}
        'unexpected' {throw [InvalidOperationException]::new('Synthetic unexpected')}
    }
    [pscustomobject]@{Name='Adapter [lab]* ?';InterfaceIndex=$(if($script:mode -eq 'mismatch'){99}else{7});InterfaceGuid='synthetic';ReceivedBytes=1}
    [pscustomobject]@{Name='Adapter labX Z';InterfaceIndex=8;ReceivedBytes=2}
}
$good=Invoke-DiagnosticCheck 'AdapterStatistics:7' {Invoke-AdapterDetail AdapterStatistics 'Adapter [lab]* ?' 7 'synthetic'}
Assert-Fix ($good.Status -eq 'Success' -and $good.Data.Count -eq 1 -and $good.Data[0].Fields.ReceivedBytes -eq 1) 'Literal wildcard/spaces alias matches exactly'
$absent=Invoke-DiagnosticCheck 'AdapterStatistics:9' {Invoke-AdapterDetail AdapterStatistics 'absent' 9 'synthetic'}
Assert-Fix ($absent.Status -eq 'Unavailable' -and $absent.Error.Explanation -eq 'No matching adapter-provider object was returned.' -and $absent.Error.AdapterIdentity.InterfaceIndex -eq 9) 'Missing literal target unavailable with identity'
foreach($case in @(@('missing','Unavailable'),@('denied','PermissionDenied'),@('unexpected','Failed'),@('mismatch','Failed'))){
    $script:mode=$case[0]
    $result=Invoke-DiagnosticCheck 'AdapterStatistics:7' {Invoke-AdapterDetail AdapterStatistics 'Adapter [lab]* ?' 7 'synthetic'}
    Assert-Fix ($result.Status -eq $case[1]) "Provider status $($case[0])"
    if($case[0] -eq 'missing'){Assert-Fix ($result.Error.Message -eq 'Original localized message' -and $result.Error.Id -eq 'CmdletizationQuery_NotFound_Name,Get-NetAdapterStatistics' -and $result.Error.Category -eq 'ObjectNotFound') 'Original error preserved'}
}
function Get-NetAdapterPowerManagement {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    Assert-Fix ($Name -eq '*' -and $IncludeHidden) 'Power includes hidden inventory'
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([Exception]::new('Power provider absent'),'CmdletizationQuery_NotFound_Name',[Management.Automation.ErrorCategory]::ObjectNotFound,$Name))
}
$power=Invoke-DiagnosticCheck 'AdapterPowerManagement:7' {Invoke-AdapterDetail AdapterPowerManagement 'Adapter [lab]* ?' 7 'synthetic'}
Assert-Fix ($power.Status -eq 'Unavailable' -and $power.Error.Id -eq 'CmdletizationQuery_NotFound_Name,Get-NetAdapterPowerManagement') 'Power missing provider scoped classification'
$unrelated=Invoke-DiagnosticCheck 'unrelated' {throw [Management.Automation.ErrorRecord]::new([Exception]::new('missing'),'OtherMissing',[Management.Automation.ErrorCategory]::ObjectNotFound,$null)}
Assert-Fix ($unrelated.Status -eq 'Failed') 'Unrelated object missing not relabelled'
function C {param($Name,$Data);[pscustomobject]@{Name=$Name;Status='Success';Data=@($Data);StartedAt='2026-01-01T00:00:00Z';CompletedAt='2026-01-01T00:00:01Z'}}
$adapters=@()
foreach($spec in @(@(1,'Up',$true),@(2,'Disconnected',$true),@(3,'Up',$false),@(4,'Up',$true))){$adapters += [pscustomobject]@{InterfaceIndex=$spec[0];Name="Synthetic <$($spec[0])>";InterfaceDescription='<description>';Status=$spec[1];HardwareInterface=$spec[2]}}
$addresses=@()
foreach($i in @(2,3,1,9,1)){$addresses += [pscustomobject]@{InterfaceIndex=$i;InterfaceAlias='<alias>';IPAddress="169.254.$i.$($addresses.Count+1)";AddressState=99;PrefixOrigin=99;SuffixOrigin=5}}
$addresses += [pscustomobject]@{InterfaceIndex=4;IPAddress='192.0.2.4'}
$checks=@((C Adapters $adapters),(C IPAddresses $addresses),(C Routes @([pscustomobject]@{InterfaceIndex=4;DestinationPrefix='0.0.0.0/0'})),(C DHCPAndGateways @([pscustomobject]@{InterfaceIndex=1;DHCPEnabled=$true})))
$f=Get-DiagnosticFindings $checks
Assert-Fix ($f.ApipaDetails.Count -eq 5 -and $f.ApipaDetails[0].InterfaceIndex -eq 1 -and $f.ApipaDetails[1].InterfaceIndex -eq 1) 'All APIPA retained; active physical first, multiple addresses retained'
Assert-Fix (@($f.ApipaDetails | Where-Object InterfaceIndex -eq 4).Count -eq 0) 'Healthy physical not attributed other APIPA'
Assert-Fix (($f.ApipaDetails | Where-Object InterfaceIndex -eq 2).Observation -match 'does not establish a current internet-path fault') 'Disconnected context'
Assert-Fix (($f.ApipaDetails | Where-Object InterfaceIndex -eq 3).Hypothesis -match 'does not establish.*harmless') 'Virtual is not automatically harmless'
Assert-Fix (($f.ApipaDetails | Where-Object InterfaceIndex -eq 9).Kind -eq 'Unknown' -and ($f.ApipaDetails | Where-Object InterfaceIndex -eq 9).Observation -match 'Missing sources') 'Missing metadata explicit'
Assert-Fix ($f.ApipaDetails[0].Hypothesis -match 'one possibility' -and $f.ApipaDetails[0].Observation -match 'Unknown \(99\)') 'Conditional DHCP hypothesis and unknown enum retention'
Assert-Fix ($f.ApipaDetails[0].EvidenceReferences.Count -gt 0 -and $f.ApipaDetails[0].StartedAt) 'Evidence references/times retained'
$timed=[pscustomobject]@{Name='AdapterStatistics:8';Status='TimedOut';Data=@();Error=@{Message='Worker deadline'}}
$e=[pscustomobject]@{Checks=@($checks)+@($absent,$good,$timed);Findings=$f}
$paths=Write-DiagnosticReport $e (Join-Path $root ('output\tests\adapter-apipa-'+[guid]::NewGuid().ToString('N')))
$html=Get-Content -Raw $paths.HtmlPath
Assert-Fix ($html.Contains('&lt;description&gt;') -and $html.Contains('&lt;alias&gt;') -and -not $html.Contains('<description>')) 'Finding text encoded'
Assert-Fix ((Get-CheckSummary @($absent)).CollectionStatus -eq 'Unavailable' -and ($e.LogicalNetwork.Coverage | Where-Object Source -eq 'AdapterStatistics:9').Status -eq 'Unavailable' -and $html.Contains('No matching adapter-provider object was returned.')) 'Summary, JSON and map agree on missing provider'
Assert-Fix (($e.LogicalNetwork.Coverage | Where-Object Source -eq 'AdapterStatistics:8').Status -eq 'TimedOut') 'Worker deadline remains distinct'
Write-Host "PASS: $script:count adapter/APIPA assertions."
