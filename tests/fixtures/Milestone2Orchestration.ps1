# Shared synthetic collector; never invokes native providers or connectivity probes.
$mock = {
    param($definition, $timeout, $directory)
    if ($definition.FunctionName -eq 'Invoke-ConnectivityProbe') {
        Assert-Condition ($timeout -eq 25 -and $definition.Arguments.TimeoutMs -eq 10000) 'Separate probe and worker budgets, including resolution'
    }
    $script:executed += $definition
    $data = @()
    switch ($definition.Name) {
        'Adapters' { $data = @([pscustomobject]@{ InterfaceIndex = 7; Name = 'Lab'; InterfaceDescription = 'Synthetic'; HardwareInterface = $true; Status = 'Up'; InterfaceType = 6; MacAddress = '00-00-00-00-00-00'; LinkSpeed = '1 Gbps' }) }
        'IPAddresses' { $data = @([pscustomobject]@{ InterfaceIndex = 7; IPAddress = '192.0.2.2'; PrefixLength = 24; AddressState = 'Preferred'; AddressFamily = 2 }, [pscustomobject]@{ InterfaceIndex = 7; IPAddress = '2001:db8::2'; PrefixLength = 64; AddressState = 'Tentative'; AddressFamily = 23 }) }
        'Routes' { $data = @([pscustomobject]@{ InterfaceIndex = 7; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.0.2.1'; RouteMetric = 10; AddressFamily = 2 }, [pscustomobject]@{ InterfaceIndex = 7; DestinationPrefix = '::/0'; NextHop = 'fe80::1'; RouteMetric = 20; AddressFamily = 23 }) }
        'DNSServers' { $data = @([pscustomobject]@{ InterfaceIndex = 7; AddressFamily = 2; ServerAddresses = @('192.0.2.53') }) }
        'InterfacesAndMetrics' { $data = @([pscustomobject]@{ InterfaceIndex = 7; AddressFamily = 2; InterfaceMetric = 25 }) }
        'NICServices' { $data = @([pscustomobject]@{ ServiceName = 'SyntheticDriver' }) }
    }
    if ($definition.FunctionName -eq 'Invoke-ConnectivityProbe') {
        $addresses = @()
        if ($definition.Arguments.Kind -eq 'Resolve') { $addresses = @([pscustomobject]@{ IPAddress = '192.0.2.8'; AddressFamily = 'InterNetwork' }, [pscustomobject]@{ IPAddress = '2001:db8::8'; AddressFamily = 'InterNetworkV6' }) }
        $data = @([pscustomobject]@{ Kind = $definition.Arguments.Kind; Destination = $definition.Arguments.Destination
            Outcome = $(if ($definition.Arguments.Kind -eq 'Resolve') { 'Success' } else { 'Failed' })
            Error = 'Synthetic refusal/no response; no root cause established'; Evidence = $addresses; ObservedConnection = $null })
    }
    $isTimeout=$definition.Name -eq 'Windows'
    [pscustomobject]@{ Name = $definition.Name; Status = $(if ($isTimeout) { 'TimedOut' } else { 'Success' }); Data = $data; Request = $definition.Arguments
        StartedAt='2026-01-01T00:00:00+00:00';CompletedAt=([DateTimeOffset]'2026-01-01T00:00:00+00:00').AddSeconds($(if($isTimeout){$timeout}else{0})).ToString('o')
        DurationMs=$(if($isTimeout){$timeout*1000}else{0});TimeoutSeconds=$timeout;TimeoutScope=$(if($isTimeout){'Worker'}else{$null})
        Error=$(if($isTimeout){[pscustomobject]@{Id='CheckTimeout';Category='OperationTimeout';Message='Synthetic worker deadline; no live provider invoked.'}}else{$null}) }
}

function Assert-Milestone2Continuation {
    param($Evidence,[object[]]$Executed,$Saved)
    # Independent expected fixture contract: all passive families, one adapter's
    # details, seven event groups, then the parent-generated skipped probe record.
    # Do not derive this list from PlannedChecks: an omitted scheduling family
    # must fail even when both the plan and resulting evidence omit it.
    $expected=@('Windows','TimeZone','Adapters','NICDrivers','IPAddresses','DHCPAndGateways','DNSServers',
        'InterfacesAndMetrics','Routes','Neighbours','WiFiConnection','NICServices',
        'Proxy:User','Proxy:Machine','Proxy:WinHTTP','VPN:User','VPN:AllUsers','AdapterBindings',
        'DNS:EffectivePolicy','DNS:GlobalSettings',
        'AdapterStatistics:7','AdapterPowerManagement:7',
        'Events:System:Network','Events:System:NIC','Events:System:Power',
        'Events:Microsoft-Windows-Dhcp-Client/Admin','Events:Microsoft-Windows-Dhcp-Client/Operational',
        'Events:Microsoft-Windows-WLAN-AutoConfig/Operational','Events:Microsoft-Windows-Wired-AutoConfig/Operational','Connectivity')
    $workerNames=$expected[0..($expected.Count-2)]
    Assert-Condition (($Executed.Name -join '|') -ceq ($workerNames -join '|')) 'Every expected worker executes in order after timeout, exactly once'
    foreach($item in @($Evidence,$Saved)){
        Assert-Condition (($item.Checks.Name -join '|') -ceq ($expected -join '|')) 'All expected result records retained in order, without missing or duplicate checks'
        Assert-Condition (($item.PlannedChecks -join '|') -ceq ($workerNames -join '|')) 'Plan accounts for every worker, excluding parent-generated skipped connectivity'
        $first=$item.Checks[0]
        Assert-Condition ($first.Name -eq 'Windows' -and $first.Status -eq 'TimedOut' -and $first.TimeoutScope -eq 'Worker' -and $first.Error.Id -eq 'CheckTimeout' -and $first.Error.Category -eq 'OperationTimeout') 'First timeout retains worker scope and original error details'
        Assert-Condition ($first.StartedAt -and $first.CompletedAt -and $first.DurationMs -eq 30000 -and $first.TimeoutSeconds -eq 30 -and $first.Error.Message -eq 'Synthetic worker deadline; no live provider invoked.') 'Timeout timestamps, duration, budget and message retained'
        Assert-Condition (@($item.Checks[1..($workerNames.Count-1)] | Where-Object Status -ne 'Success').Count -eq 0 -and $item.Checks[-1].Status -eq 'Skipped') 'Subsequent collectors succeed and passive connectivity remains skipped'
        Assert-Condition ($item.CollectionStatus -eq 'Complete' -and $item.CompletedAt -and $null -eq $item.PendingCheck -and $null -eq $item.CollectionError) 'Final collection is complete with timestamp and no pending check/error'
    }
    Assert-Condition ($Saved.RunId -eq $Evidence.RunId -and $Saved.CompletedAt -eq $Evidence.CompletedAt -and $Saved.Revision -eq $Evidence.Revision) 'Persisted final completion belongs to this run and revision'
}
