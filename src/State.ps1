function Set-AtomicText {
    param([string]$Path, [string]$Text)
    $temporary = $null
    $parent = $null
    try {
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        # GetDirectoryName on some .NET Framework builds rejects long paths
        # that File.Open/Move support. The provider already resolved this path;
        # retain its directory verbatim, including a drive/UNC root separator.
        $parent = $Path.Substring(0, $Path.LastIndexOfAny([char[]]'\/') + 1)
        # Same directory/volume, full random identity and exclusive creation,
        # without repeating the report basename in the temporary filename.
        $temporary = [IO.Path]::Combine($parent, ([guid]::NewGuid().ToString('N') + '.tmp'))
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        # Indexers and sync clients can briefly open a destination without delete
        # sharing. Retry the atomic operation; never fall back to delete-then-move.
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, ($Path + '.bak')) }
                else { [IO.File]::Move($temporary, $Path) }
                break
            } catch {
                if ($attempt -eq 9 -or -not [IO.File]::Exists($temporary)) { throw }
                Start-Sleep -Milliseconds 200
            }
        }
    } catch {
        $native = $_.Exception.GetBaseException()
        if ($native -is [IO.PathTooLongException]) {
            throw [IO.PathTooLongException]::new('Atomic report path is too long for this runtime. Use a shorter checkout/output path, allowing room for temporary and .bak filenames. The native failure is retained as InnerException.', $native)
        }
        if ($native -is [IO.DirectoryNotFoundException] -and [IO.Directory]::Exists($parent) -and
            ($temporary.Length -ge 260 -or ($Path.Length + 4) -ge 260)) {
            throw [IO.DirectoryNotFoundException]::new('Atomic report directory could not be resolved although its parent was observed present. This long path may exceed runtime limits; try a shorter checkout/output path. A concurrent directory change is also possible. The native failure is retained as InnerException.', $native)
        }
        throw
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-DiagnosticEvidence {
    param([Parameter(Mandatory)][string]$Path)
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        $recovered = Get-Content -LiteralPath ($Path + '.bak') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $recovered.CollectionStatus = 'Incomplete'
        $recovered.CompletedAt = $null
        $recovered | Add-Member -NotePropertyName RecoveryNote -NotePropertyValue 'Recovered previous checkpoint; latest revision could not be read.' -Force
        return $recovered
    }
}

function New-SnapshotIdentity {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    [pscustomobject]@{ ComputerName = [Environment]::MachineName; RunId = [guid]::NewGuid().ToString('D')
        CollectorVersion = '0.6.0'; IsElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        StartedAt = [DateTimeOffset]::Now.ToString('o') }
}

function New-DiagnosticRunDirectory {
    param([string]$RepositoryRoot,[string]$OutputRoot,[string]$Mode,$Identity)
    if(-not $OutputRoot){$OutputRoot=Join-Path $RepositoryRoot 'output'}
    $resolved=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
    $directory=Join-Path $resolved ($Mode.ToLower()+'-'+($Identity.ComputerName -replace '[^A-Za-z0-9_.-]','_')+'-'+$Identity.RunId)
    if([IO.Directory]::Exists($directory) -or [IO.File]::Exists($directory)){throw "Run destination already exists: $directory"}
    $null=[IO.Directory]::CreateDirectory($directory)
    # Protect a custom output root inside a Git worktree too, without editing
    # the caller's root ignore file or any pre-existing report directory.
    [IO.File]::WriteAllText((Join-Path $directory '.gitignore'),"*`r`n")
    Write-Host "Run directory: $directory"
    $directory
}

function Get-RunMetadata {
    param($Identity,[string]$Mode)
    $buildRevision=$null;$buildStatus='Unavailable';$buildReason='No embedded build revision; Git is not required or invoked at collection time.'
    $buildPath=Join-Path $PSScriptRoot 'BuildInfo.json'
    if([IO.File]::Exists($buildPath)){
        try{
            if((Get-Item -LiteralPath $buildPath).Length -gt 4096){throw 'Embedded build metadata exceeds 4096 bytes.'}
            $build=[IO.File]::ReadAllText($buildPath) | ConvertFrom-Json -ErrorAction Stop
            if($build.CollectorVersion -ne $Identity.CollectorVersion -or $build.Revision -notmatch '^[0-9a-f]{40}$'){throw 'Embedded build version/revision invalid.'}
            $buildRevision=[string]$build.Revision;$buildStatus='Embedded';$buildReason='Packaged src/BuildInfo.json; does not assert that local files are unmodified.'
        }catch{$buildStatus='Unavailable';$buildReason=$_.Exception.Message}
    }
    [pscustomobject]@{ContractVersion=1;CollectorVersion=$Identity.CollectorVersion;Mode=$Mode;RunId=$Identity.RunId
        Runtime=[pscustomobject]@{Version=$PSVersionTable.PSVersion.ToString();Edition='Windows PowerShell';Provenance='Executing PowerShell process'}
        OS=[pscustomobject]@{Version=[Environment]::OSVersion.Version.ToString();Provenance='System.Environment.OSVersion (may be compatibility affected)';WindowsCheckPath=$null;Status='RuntimeReported';Reason='Authoritative Windows provider evidence, when collected, remains in Checks.'}
        BuildRevision=$buildRevision;BuildRevisionStatus=$buildStatus;BuildRevisionReason=$buildReason
        Contracts=[pscustomobject]@{Schema=10;Publication=1;Analysis=1;Context=4;ObservationComparison=4;Timing=1;LeaseTimestamp=1}}
}

function Get-InterfaceSummary {
    param([object[]]$Checks)
    $names = @('Adapters','IPAddresses','DHCPAndGateways','DNSServers','Routes','InterfacesAndMetrics')
    $data = @{}
    $states = [ordered]@{}
    foreach ($name in $names) {
        $check = @($Checks | Where-Object Name -eq $name | Select-Object -Last 1)
        $states[$name] = $(if ($check.Count -eq 0) { 'NotCollected' } else { $check[0].Status })
        $data[$name] = @($check | Where-Object Status -eq 'Success' | ForEach-Object { $_.Data })
    }
    $indices = @($names | ForEach-Object { $data[$_] } | Where-Object { $null -ne $_.InterfaceIndex } |
        ForEach-Object { $_.InterfaceIndex } | Sort-Object -Unique)
    foreach ($index in $indices) {
        $adapters = @($data.Adapters | Where-Object InterfaceIndex -eq $index | Select-Object Name,InterfaceIndex,InterfaceDescription,
            @{n='Kind';e={ if ($null -eq $_.HardwareInterface) { 'Unknown' } elseif ($_.HardwareInterface) { 'Physical' } else { 'Virtual/software' } }},
            Status,LinkSpeed,MacAddress)
        $metrics = @($data.InterfacesAndMetrics | Where-Object InterfaceIndex -eq $index)
        $routes = @($data.Routes | Where-Object { $_.InterfaceIndex -eq $index -and $_.DestinationPrefix -in @('0.0.0.0/0','::/0') } |
            ForEach-Object {
                $route = $_
                [pscustomobject]@{ DestinationPrefix = $route.DestinationPrefix; NextHop = $route.NextHop; AddressFamily = $route.AddressFamily
                    RouteMetric = $route.RouteMetric; RouteReportedInterfaceMetric = $route.InterfaceMetric
                    InterfaceMetrics = @($metrics | Where-Object AddressFamily -eq $route.AddressFamily | Select-Object AddressFamily,InterfaceMetric,AutomaticMetric) }
            })
        [pscustomobject]@{ InterfaceIndex = $index; Adapters = $adapters
            Addresses = @($data.IPAddresses | Where-Object InterfaceIndex -eq $index | Select-Object IPAddress,PrefixLength,AddressFamily,AddressState)
            DHCP = @($data.DHCPAndGateways | Where-Object InterfaceIndex -eq $index | Select-Object DHCPEnabled,DHCPServer,DHCPLeaseObtained,DHCPLeaseExpires)
            DefaultRoutes = $routes; InterfaceMetrics = $metrics
            DNS = @($data.DNSServers | Where-Object InterfaceIndex -eq $index | Select-Object AddressFamily,ServerAddresses)
            SourceStatus = [pscustomobject]$states }
    }
}
