function Invoke-SnapshotRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$PreviousSnapshotPath, [string]$ExpectationsPath,
        [ValidateRange(1,168)][int]$LookbackHours = 24,
        [ValidateRange(1,1000)][int]$MaxEventsPerLog = 200,
        [ValidateRange(1,1000)][int]$MaxNicEvents = 200,
        [ValidateRange(1,1000)][int]$MaxPowerEvents = 100,
        [ValidateRange(1,600)][int]$CheckTimeoutSeconds = 30,
        [switch]$IncludeConnectivityTests, [switch]$IncludeGatewayPing, [switch]$IncludeLegacyDnsTargets,
        [ValidateCount(1,16)][string[]]$TcpDestinations = @('1.1.1.1','2606:4700:4700::1111'),
        [ValidateRange(1,65535)][int]$TcpPort = 443,
        [string]$DnsQueryName = 'example.com', [string]$HttpsEndpoint = 'https://example.com/',
        [ValidateRange(1,60)][int]$ProbeTimeoutSeconds = 10,
        [ValidateRange(5,120)][int]$ProbeWorkerOverheadSeconds = 15,
        # Injection seams are for dependency-free orchestration tests, never CLI options.
        [scriptblock]$CheckExecutor, [scriptblock]$CheckpointObserver, [string]$TestOutputRoot)
    if ($IncludeGatewayPing -and -not $IncludeConnectivityTests) { throw 'IncludeGatewayPing requires IncludeConnectivityTests.' }
    if ($IncludeLegacyDnsTargets -and -not $IncludeConnectivityTests) { throw 'IncludeLegacyDnsTargets requires IncludeConnectivityTests.' }
    $uri = $null
    if (-not [uri]::TryCreate($HttpsEndpoint, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'HttpsEndpoint must be HTTPS without user information, query, or fragment.' }
    foreach ($target in @($TcpDestinations) + @($DnsQueryName)) {
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match '[\s/@?\x00-\x1f]') { throw 'Destinations/query names must be hostnames or IP literals without credentials or URL components.' }
    }
    $identity = New-SnapshotIdentity
    $computer = $identity.ComputerName -replace '[^A-Za-z0-9_.-]', '_'
    $outputRoot = $(if ($TestOutputRoot) { $TestOutputRoot } else { Join-Path $RepositoryRoot 'output' })
    $directory = Join-Path $outputRoot ("snapshot-$computer-$($identity.RunId)")
    $null = New-Item -Path $directory -ItemType Directory -ErrorAction Stop
    $evidence = [pscustomobject]@{ SchemaVersion = 7; Mode = 'Snapshot'; ComputerName = $identity.ComputerName
        RunId = $identity.RunId; CollectorVersion = $identity.CollectorVersion; IsElevated = $identity.IsElevated
        StartedAt = $identity.StartedAt; CollectedAt = $identity.StartedAt; CompletedAt = $null
        CollectionStatus = 'Incomplete'; PendingCheck = $null; Revision = 0; PlannedChecks = @()
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Parameters = [pscustomobject]@{ LookbackHours = $LookbackHours; MaxEventsPerLog = $MaxEventsPerLog
            PreviousSnapshotRequested = [bool]$PreviousSnapshotPath; ExpectationsRequested = [bool]$ExpectationsPath
            MaxNicEvents = $MaxNicEvents; MaxPowerEvents = $MaxPowerEvents; CheckTimeoutSeconds = $CheckTimeoutSeconds
            IncludeLegacyDnsTargets = [bool]$IncludeLegacyDnsTargets; IncludeConnectivityTests = [bool]$IncludeConnectivityTests; IncludeGatewayPing = [bool]$IncludeGatewayPing
            TcpDestinations = $TcpDestinations; TcpPort = $TcpPort; DnsQueryName = $DnsQueryName
            HttpsEndpoint = $HttpsEndpoint; ProbeTimeoutSeconds = $ProbeTimeoutSeconds; ProbeWorkerOverheadSeconds = $ProbeWorkerOverheadSeconds }
        ContextInputs = @(); Checks = @(); Findings = Get-DiagnosticFindings @(); CollectionError = $null }
    $source = Join-Path $RepositoryRoot 'src'
    # This closure runs only in the parent. All worker inputs are serialized explicitly.
    $save = {
        $evidence.Revision++
        $evidence.Findings = Get-DiagnosticFindings $evidence.Checks
        $null = Write-DiagnosticReport $evidence $directory
        if ($null -ne $CheckpointObserver) { & $CheckpointObserver $evidence $directory }
    }
    $execute = {
        param($definition)
        $evidence.PlannedChecks += $definition.Name
        $evidence.PendingCheck = $definition.Name
        & $save
        $timeout = $CheckTimeoutSeconds
        if ($definition.FunctionName -eq 'Invoke-ConnectivityProbe') {
            $timeout = $ProbeTimeoutSeconds + $ProbeWorkerOverheadSeconds
        } elseif ($definition.TimeoutSeconds) { $timeout = [Math]::Min($timeout, [int]$definition.TimeoutSeconds) }
        if ($definition.SkipReason) {
            $result = [pscustomobject]@{ Name = $definition.Name; Status = 'Skipped'; Request = $definition.Arguments; Error = $null
                Data = @([pscustomobject]@{ Kind = 'DNS'; Destination = $definition.Arguments.Destination; DnsTarget = $definition.Arguments.DnsTarget
                    Outcome = 'Skipped'; SkipReason = $definition.SkipReason; DurationMs = $null; DnsError = $null
                    Evidence = [pscustomobject]@{ QueryName = $definition.Arguments.QueryName; QueryType = $definition.Arguments.QueryType } }) }
        } elseif ($null -ne $CheckExecutor) { $result = & $CheckExecutor $definition $timeout $directory }
        else { $result = Invoke-BoundedCheck -Definition $definition -SourceDirectory $source -WorkingDirectory $directory -TimeoutSeconds $timeout }
        $evidence.Checks += $result
        $evidence.PendingCheck = $null
        & $save
    }
    try {
        & $save
        foreach ($inputSpec in @(@('Baseline',$PreviousSnapshotPath),@('Expectations',$ExpectationsPath))) {
            if (-not $inputSpec[1]) { continue }
            # Resolve against the caller's working directory before entering a worker.
            # Only bounded workers read optional input; failures cannot discard collection.
            $evidence.PendingCheck = 'ContextInput:' + $inputSpec[0]
            & $save
            try {
                $inputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($inputSpec[1])
                $definition = [pscustomobject]@{Name=$inputSpec[0];FunctionName='Read-ContextInput';Arguments=@{Path=$inputPath;Kind=$inputSpec[0];ComputerName=$identity.ComputerName}}
                $evidence.ContextInputs += Invoke-BoundedCheck -Definition $definition -SourceDirectory $source -WorkingDirectory $directory -TimeoutSeconds $CheckTimeoutSeconds
            } catch {
                $evidence.ContextInputs += [pscustomobject]@{Name=$inputSpec[0];Status='Failed';Data=@();Error=[pscustomobject]@{Message=$_.Exception.Message;Id=$_.FullyQualifiedErrorId}}
            }
            $evidence.PendingCheck = $null
            & $save
        }
        foreach ($name in @('Windows','TimeZone','Adapters','NICDrivers','IPAddresses','DHCPAndGateways','DNSServers',
            'InterfacesAndMetrics','Routes','Neighbours','WiFiConnection','NICServices')) {
            & $execute ([pscustomobject]@{ Name = $name; FunctionName = 'Invoke-SnapshotCollector'; Arguments = @{ Name = $name } })
        }
        $adapterInventory = @($evidence.Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
        foreach ($kind in @('AdapterStatistics','AdapterPowerManagement')) {
            if (-not $adapterInventory.Count) {
                $evidence.Checks += [pscustomobject]@{Name=$kind;Status='Unavailable';Data=@();Error=[pscustomobject]@{Message='Adapter inventory unavailable or empty; no adapter detail checks scheduled.'}}
            }
            foreach ($adapter in $adapterInventory) {
                & $execute ([pscustomobject]@{Name=($kind+':'+$adapter.InterfaceIndex);FunctionName='Invoke-AdapterDetail';Arguments=@{Kind=$kind;AdapterName=[string]$adapter.Name;InterfaceIndex=[int]$adapter.InterfaceIndex;InterfaceGuid=[string]$adapter.InterfaceGuid}})
            }
        }
        $end = [DateTimeOffset]::Parse($identity.StartedAt).LocalDateTime
        $services = @($evidence.Checks | Where-Object { $_.Name -eq 'NICServices' -and $_.Status -eq 'Success' } |
            ForEach-Object { $_.Data } | ForEach-Object { $_.ServiceName } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($definition in @(Get-EventDefinitions -StartTime $end.AddHours(-$LookbackHours) -EndTime $end -NetworkLimit $MaxEventsPerLog -NicLimit $MaxNicEvents -PowerLimit $MaxPowerEvents -NicServices $services)) {
            & $execute $definition
        }
        if ($IncludeConnectivityTests) {
            $definitions = @(Get-ConnectivityDefinitions -Checks $evidence.Checks -TcpDestinations $TcpDestinations -TcpPort $TcpPort -DnsQueryName $DnsQueryName -HttpsEndpoint $HttpsEndpoint -ProbeTimeoutSeconds $ProbeTimeoutSeconds -IncludeGatewayPing ([bool]$IncludeGatewayPing) -IncludeLegacyDnsTargets ([bool]$IncludeLegacyDnsTargets))
            foreach ($definition in $definitions) {
                & $execute $definition
                if ($definition.Arguments.Kind -eq 'Resolve') {
                    $resolved = $evidence.Checks[-1]
                    foreach ($address in @($resolved.Data | Where-Object Outcome -eq 'Success' | ForEach-Object { $_.Evidence })) {
                        $kind = $(if ($definition.Name -eq 'Connectivity:Resolve:HTTPS') { 'HTTPS' } else { 'TCP' })
                        $port = $(if ($kind -eq 'HTTPS') { $uri.Port } else { $TcpPort })
                        $arguments = @{ Kind = $kind; Destination = $address.IPAddress; Port = $port; Endpoint = $HttpsEndpoint; TimeoutMs = ($ProbeTimeoutSeconds * 1000) }
                        & $execute (New-ProbeDefinition "Connectivity:${kind}:$($definition.Arguments.Destination):$($address.IPAddress)" $arguments $ProbeTimeoutSeconds)
                    }
                }
            }
        } else {
            $evidence.Checks += [pscustomobject]@{ Name = 'Connectivity'; Status = 'Skipped'; Data = @('Active probes were not enabled.'); Error = $null }
        }
        $evidence.CollectionStatus = 'Complete'
        $evidence.CompletedAt = [DateTimeOffset]::Now.ToString('o')
        & $save
    } catch {
        $evidence.CollectionStatus = 'Incomplete'
        $evidence.CompletedAt = $null
        $evidence.CollectionError = $_.Exception.Message
        # Best effort: a previous atomic checkpoint remains readable even if storage has failed.
        try { $null = Write-DiagnosticReport $evidence $directory } catch { }
        throw
    }
    [pscustomobject]@{ JsonPath = (Join-Path $directory 'evidence.json'); HtmlPath = (Join-Path $directory 'summary.html'); Evidence = $evidence }
}
