function Convert-NetworkEvent {
    param($Event)
    $message = $null
    $messageError = $null
    try { $message = $Event.Message } catch { $messageError = $_.Exception.Message }
    [pscustomobject]@{ TimeCreated = ([DateTimeOffset]$Event.TimeCreated).ToString('o'); Id = $Event.Id
        ProviderName = $Event.ProviderName; LevelDisplayName = $Event.LevelDisplayName; RecordId = $Event.RecordId
        Message = $message; MessageError = $messageError; Xml = $Event.ToXml() }
}

function Get-RecentNetworkEvents {
    param([string]$LogName, [datetime]$StartTime, [datetime]$EndTime, [int]$MaxEvents, [string[]]$Providers = @())
    $log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
    if (-not $log.IsEnabled) { throw [NotSupportedException]::new("Event log is disabled: $LogName") }
    $providerEvidence = @()
    $supported = @()
    foreach ($provider in $Providers) {
        # Query log publisher names rather than assuming every installed OS has a provider.
        if (@($log.ProviderNames) -contains $provider) {
            $supported += $provider
            $providerEvidence += [pscustomobject]@{ Name = $provider; Status = 'Available'; Error = $null }
        } else {
            $providerEvidence += [pscustomobject]@{ Name = $provider; Status = 'Unavailable'; Error = "Provider is not registered with $LogName." }
        }
    }
    $filter = @{ LogName = $LogName; StartTime = $StartTime; EndTime = $EndTime }
    if ($Providers.Count -gt 0) { $filter.ProviderName = $supported }
    $events = @()
    if ($Providers.Count -eq 0 -or $supported.Count -gt 0) {
        try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop) }
        catch { if ($_.FullyQualifiedErrorId -notmatch '^NoMatchingEventsFound') { throw } }
    }
    [pscustomobject]@{ LogName = $LogName; StartTime = ([DateTimeOffset]$StartTime).ToString('o')
        EndTime = ([DateTimeOffset]$EndTime).ToString('o'); MaxEvents = $MaxEvents
        LimitReached = ($events.Count -eq $MaxEvents); Providers = $providerEvidence
        QueryStatus = $(if ($Providers.Count -gt 0 -and $supported.Count -eq 0) { 'Unavailable' } else { 'Success' })
        Events = @($events | ForEach-Object { Convert-NetworkEvent $_ }) }
}

function Get-EventDefinitions {
    param([datetime]$StartTime, [datetime]$EndTime, [int]$NetworkLimit, [int]$NicLimit, [int]$PowerLimit,
        [string[]]$NicServices = @())
    $groups = @(
        @{ Name = 'Network'; Limit = $NetworkLimit; Providers = @('Microsoft-Windows-Dhcp-Client','Microsoft-Windows-TCPIP','Tcpip','Microsoft-Windows-DNS-Client') }
        @{ Name = 'NIC'; Limit = $NicLimit; Providers = @('Microsoft-Windows-NDIS','Microsoft-Windows-Kernel-PnP') + @($NicServices) }
        @{ Name = 'Power'; Limit = $PowerLimit; Providers = @('Microsoft-Windows-Kernel-Power','Microsoft-Windows-Power-Troubleshooter','Microsoft-Windows-Kernel-Boot','Microsoft-Windows-Kernel-General') }
    )
    foreach ($group in $groups) {
        [pscustomobject]@{ Name = ('Events:System:' + $group.Name); FunctionName = 'Get-RecentNetworkEvents'
            Arguments = @{ LogName = 'System'; StartTime = $StartTime; EndTime = $EndTime; MaxEvents = $group.Limit
                Providers = @($group.Providers | Where-Object { $_ } | Select-Object -Unique) } }
    }
    foreach ($log in @('Microsoft-Windows-Dhcp-Client/Admin','Microsoft-Windows-Dhcp-Client/Operational',
        'Microsoft-Windows-WLAN-AutoConfig/Operational','Microsoft-Windows-Wired-AutoConfig/Operational')) {
        [pscustomobject]@{ Name = "Events:$log"; FunctionName = 'Get-RecentNetworkEvents'
            Arguments = @{ LogName = $log; StartTime = $StartTime; EndTime = $EndTime; MaxEvents = $NetworkLimit; Providers = @() } }
    }
}
