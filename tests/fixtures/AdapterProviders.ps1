function Invoke-TestStatisticsBatch {
    param($Adapters,$TimingContext)
    function Get-NetAdapterStatistics {
        [CmdletBinding()]param($Name,[switch]$IncludeHidden)
        [pscustomobject]@{InterfaceDescription='Synthetic installation identity';InstanceID='Opaque synthetic key';ReceivedBytes=100}
    }
    Invoke-ObservationStatistics -Adapters $Adapters -TimingContext $TimingContext
}
