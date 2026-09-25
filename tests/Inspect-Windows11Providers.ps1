#requires -Version 5.1
param([string]$AdapterName)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($file in 'Core','State','Execution'){. (Join-Path $root "src\$file.ps1")}
$work=Join-Path $root ('output\provider-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$report=[pscustomobject]@{ContractVersion=1;CollectionStatus='Incomplete';Identity=(New-SnapshotIdentity);Checks=@();Limitation='Sequential read-only queries, not simultaneous state. Raw CIM and cmdlet scopes can differ; no fallback counters or hardware diagnosis.'}
$path=Join-Path $work 'queries.json'
Set-AtomicText $path (ConvertTo-Json $report -Depth 24)
foreach($mode in 'Metadata','DefaultAdapters','HiddenAdapters','CimAdapters','WildcardStatistics','UnfilteredStatistics','CimStatistics'){
    $report.Checks+=Invoke-BoundedCheck ([pscustomobject]@{Name=$mode;FunctionName='Invoke-Windows11Query';Arguments=@{Mode=$mode}}) (Join-Path $root 'src') $work 10 -AdditionalSources @((Join-Path $PSScriptRoot 'fixtures\Windows11Queries.ps1'))
    Set-AtomicText $path (ConvertTo-Json $report -Depth 24)
}
$inventory=Invoke-BoundedCheck ([pscustomobject]@{Name='Adapters';FunctionName='Invoke-SnapshotCollector';Arguments=@{Name='Adapters'}}) (Join-Path $root 'src') $work 10
$report.Checks+=$inventory
Set-AtomicText $path (ConvertTo-Json $report -Depth 24)
if($AdapterName){
    $target=@($inventory.Data | Where-Object {[string]::Equals($_.Name,$AdapterName,[StringComparison]::OrdinalIgnoreCase)})
    if($inventory.Status -ne 'Success' -or $target.Count -ne 1){
        $report | Add-Member NoteProperty TargetLimitation 'Requested literal alias missing or ambiguous; targeted queries not attempted.'
    }else{
        foreach($kind in 'AdapterStatistics','AdapterPowerManagement'){
            $report.Checks+=Invoke-BoundedCheck ([pscustomobject]@{Name=$kind;FunctionName='Invoke-AdapterDetail';Arguments=@{Kind=$kind;AdapterName=$target[0].Name;InterfaceIndex=$target[0].InterfaceIndex;InterfaceGuid=$target[0].InterfaceGuid;InterfaceDescription=$target[0].InterfaceDescription;AdapterInventory=@($inventory.Data)}}) (Join-Path $root 'src') $work 10
            Set-AtomicText $path (ConvertTo-Json $report -Depth 24)
        }
    }
}
$report.CollectionStatus='Complete'
Set-AtomicText $path (ConvertTo-Json $report -Depth 24)
Write-Host "Private bounded provider evidence: $path"
