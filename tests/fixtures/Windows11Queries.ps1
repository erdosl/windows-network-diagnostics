# Read-only diagnostic follow-up functions; run only in bounded workers.
function Invoke-Windows11Query {
    param([ValidateSet('DefaultAdapters','HiddenAdapters','CimAdapters','WildcardStatistics','UnfilteredStatistics','CimStatistics','Metadata')][string]$Mode)
    switch($Mode){
        DefaultAdapters {Get-NetAdapter -ErrorAction Stop}
        HiddenAdapters {Get-NetAdapter -IncludeHidden -ErrorAction Stop}
        CimAdapters {Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapter -ErrorAction Stop}
        WildcardStatistics {Get-NetAdapterStatistics -Name '*' -IncludeHidden -ErrorAction Stop}
        UnfilteredStatistics {Get-NetAdapterStatistics -IncludeHidden -ErrorAction Stop}
        CimStatistics {Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterStatisticsSettingData -ErrorAction Stop}
        Metadata {
            [pscustomobject]@{OSVersion=[Environment]::OSVersion.Version.ToString();PowerShell=$PSVersionTable.PSVersion.ToString()}
            foreach($name in 'Get-NetAdapter','Get-NetAdapterStatistics','Get-NetAdapterPowerManagement'){
                $command=Get-Command $name -ErrorAction Stop
                [pscustomobject]@{Command=$name;ModuleVersion=[string]$command.Module.Version;Definition=$command.Definition}
            }
        }
    }
}
