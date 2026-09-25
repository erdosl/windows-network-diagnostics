#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in 'Core','State','Execution','Collection','Observation'){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1')
. (Join-Path $PSScriptRoot 'fixtures\InventoryProviders.ps1')
$script:count=0
function Assert($ok,$message){if(-not $ok){throw $message};$script:count++}
$expected=@(New-TestAdapterInventory)
$inventory=@(Invoke-SnapshotCollector Adapters)
Assert ($inventory.Count -eq 14) 'All inventory rows survive projection'
$work=New-TestWorkRoot
$r=Invoke-BoundedCheck ([pscustomobject]@{Name='Adapters';FunctionName='Invoke-SnapshotCollector';Arguments=@{Name='Adapters'}}) (Join-Path $root 'src') $work 15 -AdditionalSources @((Join-Path $PSScriptRoot 'fixtures\InventoryProviders.ps1'))
Assert ($r.Status -eq 'Success' -and $r.Data.Count -eq 14) 'Worker preserves full unfiltered inventory'
foreach($row in $expected){
    $match=@($r.Data | Where-Object InterfaceGuid -eq $row.InterfaceGuid)
    Assert ($match.Count -eq 1 -and $match[0].Name -ceq $row.Name -and $match[0].Status -eq $row.Status) 'Literal alias/state/identity retained through worker JSON'
}
function Get-NetAdapterPowerManagement {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    if(-not $IncludeHidden -or $Name -cne [Management.Automation.WildcardPattern]::Escape($script:target.Name)){throw 'Incorrect literal target'}
    $script:target
}
foreach($script:target in $expected){
    $d=Invoke-DiagnosticCheck 'Power' {Invoke-AdapterDetail -Kind AdapterPowerManagement -AdapterName $script:target.Name -InterfaceIndex $script:target.InterfaceIndex -InterfaceGuid $script:target.InterfaceGuid}
    Assert ($d.Status -eq 'Success') 'Targeted aliases escaped independently of inventory'
}
$dhcp=@($expected | ForEach-Object {[pscustomobject]@{SettingID=$_.InterfaceGuid;InterfaceIndex=$_.InterfaceIndex;DHCPEnabled=$false;DHCPServer=$null;DefaultIPGateway=@();DNSServerSearchOrder=@();DNSDomain=$null;DHCPLeaseObtained=$null;DHCPLeaseExpires=$null}})
$checks=@([pscustomobject]@{Name='Adapters';Status='Success';Data=@($r.Data)},[pscustomobject]@{Name='DHCPAndGateways';Status='Success';Data=$dhcp})
$state=Get-ObservationDhcpState $checks
Assert ($state.Status -eq 'Success' -and $state.Records.Count -eq 14) 'Complete inventory enables all DHCP associations'
Assert ((Compare-ObservationDhcpState $state $state).Coverage -eq 'Complete') 'Valid DHCP comparisons retain complete coverage'
$checks[0].Data=@($r.Data | Where-Object InterfaceIndex -ne 7)
$partial=Get-ObservationDhcpState $checks
Assert ($partial.Records.Count -eq 14 -and @($partial.Records | Where-Object {$_.Reasons.Code -contains 'UnmatchedConfiguration'}).Count -eq 1) 'Unmatched DHCP record preserved explicitly'
Assert (@((Compare-ObservationDhcpState $partial $partial).Adapters | Where-Object Outcome -eq 'Not assessed').Count -eq 1) 'Unmatched comparison remains unassessed'
# Stop must promote native nonterminating provider errors before a success result.
$script:statisticsMode='Empty'
function Get-NetAdapterStatistics {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden)
    if(-not $IncludeHidden -or ($script:statisticsMode -ne 'Error' -and $Name -ne '*')){throw 'Incorrect statistics batch scope'}
    switch($script:statisticsMode){
        Empty {return}
        Unmatched {[pscustomobject]@{Name='Unrelated provider identity';ReceivedBytes=1};return}
        Matched {$expected[0];return}
        Throw {throw [InvalidOperationException]::new('Synthetic terminating query failure')}
    }
    $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('Synthetic native provider failure'),'SyntheticProviderFailure',[Management.Automation.ErrorCategory]::InvalidOperation,$Name))
    $expected[0]
}
foreach($mode in 'Empty','Unmatched','Matched','Throw'){
    $script:statisticsMode=$mode
    $batch=Invoke-DiagnosticCheck 'ObservationStatistics' {Invoke-ObservationStatistics @($expected[0])}
    switch($mode){
        Empty {Assert ($batch.Status -eq 'Success' -and $batch.Data[0].Error.ProviderDiagnostic.Outcome -eq 'ProviderRowsAbsent' -and $batch.Data[0].Error.ProviderDiagnostic.RowCount -eq 0) 'True empty batch remains distinct from query failure'}
        Unmatched {Assert ($batch.Data[0].Error.ProviderDiagnostic.Outcome -eq 'PresentUnmatched' -and $batch.Data[0].Error.ProviderDiagnostic.RowCount -eq 1) 'Unmatched batch rows retained'}
        Matched {Assert ($batch.Data[0].Status -eq 'Success' -and $batch.Data[0].Data[0].ProviderDiagnostic.Outcome -eq 'Matched') 'Successful batch matching'}
        Throw {Assert ($batch.Status -eq 'Failed' -and $batch.Error.ProviderDiagnostic.QueryStatus -eq 'Failed') 'Terminating batch query failure retained'}
    }
}
$script:statisticsMode='Error'
$batch=Invoke-DiagnosticCheck 'ObservationStatistics' {Invoke-ObservationStatistics $expected}
Assert ($batch.Status -eq 'Failed' -and $batch.Error.ProviderDiagnostic.QueryStatus -eq 'Failed' -and $batch.Error.Id -match 'SyntheticProviderFailure') 'Nonterminating batch error cannot become successful empty enumeration'
$detail=Invoke-DiagnosticCheck 'Statistics' {Invoke-AdapterDetail -Kind AdapterStatistics -AdapterName 'Ethernet' -InterfaceIndex 1 -InterfaceGuid $expected[0].InterfaceGuid}
Assert ($detail.Status -eq 'Failed' -and $detail.Error.ProviderDiagnostic.NativeException) 'Nonterminating targeted error retained'
Write-Host "PASS: $script:count inventory/targeting/DHCP/error-stream assertions; synthetic providers and real worker serialization."
