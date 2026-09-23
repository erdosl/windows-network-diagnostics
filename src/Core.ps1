function Get-AddressClassification {
    param([AllowNull()][AllowEmptyString()][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return 'Invalid' }
    if ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($parsed.IsIPv6LinkLocal) { return 'IPv6LinkLocal' }
        return 'IPv6'
    }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return 'APIPA' }
    return 'IPv4'
}

function Invoke-DiagnosticCheck {
    param([string]$Name, [scriptblock]$Action)
    $started = [DateTimeOffset]::Now.ToString('o')
    # Buffer results: never present partial output as a successful check.
    try {
        $ErrorActionPreference = 'Stop'
        $data = @(& $Action)
        [pscustomobject]@{ Name = $Name; StartedAt = $started; Status = 'Success'; Data = $data; Error = $null }
    } catch {
        $status = 'Failed'
        if ($_.Exception -is [UnauthorizedAccessException] -or $_.CategoryInfo.Category -eq 'PermissionDenied' -or
            $_.Exception.Message -match '(?i)access.*denied|permission|0x80070005|requires elevation|returns error 5\b') { $status = 'PermissionDenied' }
        elseif ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -or
            $_.FullyQualifiedErrorId -match 'NoMatchingLogsFound|NoMatchingProvidersFound' -or
            $_.Exception -is [System.NotSupportedException]) { $status = 'Unavailable' }
        [pscustomobject]@{ Name = $Name; StartedAt = $started; Status = $status; Data = @(); Error = [pscustomobject]@{
            Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category
        } }
    }
}

function Get-DiagnosticFindings {
    param([object[]]$Checks)
    $observations = @()
    $hypotheses = @()
    $addresses = @($Checks | Where-Object { $_.Name -eq 'IPAddresses' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    foreach ($address in $addresses) {
        if ((Get-AddressClassification $address.IPAddress) -eq 'APIPA') {
            $observations += "APIPA address $($address.IPAddress) on interface $($address.InterfaceIndex)."
            $hypotheses += 'An IPv4 link-local address may indicate missing DHCP service or an intentional local-only configuration; this snapshot does not establish the cause.'
        }
    }
    $adapters = @($Checks | Where-Object { $_.Name -eq 'Adapters' -and $_.Status -eq 'Success' } | ForEach-Object { $_.Data })
    # IANA interface types: Ethernet=6, IEEE 802.11=71. Do not infer from localized names.
    $ethernet = @($adapters | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true -and $_.InterfaceType -eq 6 })
    $wifi = @($adapters | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true -and $_.InterfaceType -eq 71 })
    if ($ethernet.Count -gt 0 -and $wifi.Count -gt 0) {
        $observations += 'Physical Ethernet and Wi-Fi adapters are simultaneously up (link state only).'
        $hypotheses += 'Multiple active links may affect route selection; routes and metrics require review. This is not proof of a connectivity fault.'
    }
    [pscustomobject]@{ Observations = @($observations); Hypotheses = @($hypotheses | Select-Object -Unique) }
}

function Get-CheckSummary {
    param([object[]]$Checks)
    foreach ($check in $Checks) {
        $probes = @($check.Data | Where-Object { $null -ne $_.Outcome })
        if ($probes.Count -gt 0) {
            foreach ($probe in $probes) {
                [pscustomobject]@{ Name = $check.Name; CollectionStatus = $check.Status
                    ProbeOutcome = $probe.Outcome; TimeoutScope = $probe.TimeoutScope }
            }
        } else {
            [pscustomobject]@{ Name = $check.Name; CollectionStatus = $check.Status
                ProbeOutcome = $(if ($check.Name -like 'Connectivity:*') { 'Unknown (no completed result)' } else { 'Not applicable' })
                TimeoutScope = $(if ($check.Status -eq 'TimedOut') { 'Worker' } else { $null }) }
        }
    }
}

function Write-DiagnosticReport {
    param([Parameter(Mandatory)]$Evidence, [Parameter(Mandatory)][string]$OutputDirectory)
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop
    $json = ConvertTo-Json -InputObject $Evidence -Depth 16
    $jsonPath = Join-Path $OutputDirectory 'evidence.json'
    $htmlPath = Join-Path $OutputDirectory 'summary.html'
    $encode = { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
    $html = [System.Text.StringBuilder]::new()
    $null = $html.Append('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Network snapshot</title><style>body{font:16px system-ui;margin:2rem;max-width:1000px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f4f6;padding:1rem}li{margin:.5rem 0}</style></head><body><h1>Network snapshot</h1>')
    $null = $html.Append('<p>Collected: ' + (& $encode $Evidence.CollectedAt) + '</p><p>Read-only configuration evidence with opt-in connectivity probes. A snapshot does not establish a root cause or prove connectivity. Failed ICMP is not proof of unreachability; a failed DNS query alone does not establish a DNS root cause.</p>')
    $null = $html.Append('<h2>Collection identity and state</h2><dl>')
    foreach ($field in @('ComputerName','RunId','CollectorVersion','SchemaVersion','IsElevated','PowerShellVersion','StartedAt','CompletedAt','CollectionStatus','PendingCheck','Revision','CollectionError')) {
        $null = $html.Append('<dt>' + $field + '</dt><dd>' + (& $encode $Evidence.$field) + '</dd>')
    }
    $null = $html.Append('</dl><p>Incomplete means collection has not finished. Complete means all planned checks were attempted, not that they succeeded. evidence.json is authoritative; this HTML may reflect an older checkpoint.</p>')
    $null = $html.Append('<h2>Collection parameters</h2><pre>' + (& $encode (ConvertTo-Json -InputObject $Evidence.Parameters -Depth 8)) + '</pre>')
    foreach ($section in @('Observations', 'Hypotheses')) {
        $null = $html.Append('<h2>' + $section + '</h2><ul>')
        $items = @($Evidence.Findings.$section)
        if ($items.Count -eq 0) { $null = $html.Append('<li>None recorded. Missing checks may limit findings.</li>') }
        foreach ($item in $items) { $null = $html.Append('<li>' + (& $encode $item) + '</li>') }
        $null = $html.Append('</ul>')
    }
    $null = $html.Append('<h2>Interfaces</h2><p>Joined by interface index within this snapshot. Default routes are candidates, not proof of an active gateway. Empty lists may reflect missing source checks; see SourceStatus.</p>')
    $interfaces = @(Get-InterfaceSummary -Checks $Evidence.Checks)
    if ($interfaces.Count -eq 0) { $null = $html.Append('<p>No interface data available. See check statuses below.</p>') }
    foreach ($interface in $interfaces) {
        $null = $html.Append('<h3>Interface ' + (& $encode $interface.InterfaceIndex) + ': ' + (& $encode ($interface.Adapters.Name -join ', ')) + '</h3><table>')
        foreach ($field in @('Adapters','Addresses','DHCP','DefaultRoutes','InterfaceMetrics','DNS','SourceStatus')) {
            $null = $html.Append('<tr><th>' + $field + '</th><td><pre>' + (& $encode (ConvertTo-Json -InputObject $interface.$field -Depth 12)) + '</pre></td></tr>')
        }
        $null = $html.Append('</table>')
    }
    $null = $html.Append('<h2>Check summary</h2><p>CollectionStatus describes evidence collection. ProbeOutcome describes the network operation; successful collection does not mean connectivity worked. Worker timeout leaves the probe outcome unknown.</p><table><tr><th>Check</th><th>CollectionStatus</th><th>ProbeOutcome</th><th>TimeoutScope</th></tr>')
    foreach ($row in @(Get-CheckSummary -Checks $Evidence.Checks)) {
        $null = $html.Append('<tr>')
        foreach ($field in @('Name','CollectionStatus','ProbeOutcome','TimeoutScope')) {
            $null = $html.Append('<td>' + (& $encode $row.$field) + '</td>')
        }
        $null = $html.Append('</tr>')
    }
    $null = $html.Append('</table>')
    $null = $html.Append('<h2>Checks and raw evidence</h2>')
    foreach ($check in $Evidence.Checks) {
        $null = $html.Append('<h3>' + (& $encode $check.Name) + ': ' + (& $encode $check.Status) + '</h3><pre>')
        $detail = ConvertTo-Json -InputObject $check -Depth 14
        $null = $html.Append((& $encode $detail) + '</pre>')
    }
    $null = $html.Append('</body></html>')
    # Explicit UTF-8 works on Windows PowerShell 5.1 and does not depend on console encoding.
    # JSON is the canonical checkpoint. Each file is atomically replaced, not the pair.
    Set-AtomicText -Path $jsonPath -Text $json
    Set-AtomicText -Path $htmlPath -Text $html.ToString()
    [pscustomobject]@{ JsonPath = $jsonPath; HtmlPath = $htmlPath }
}
