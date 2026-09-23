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

function Get-NetworkDisplayLabel {
    param([ValidateSet('AddressFamily','ConnectionState')][string]$Kind, $Value)
    if ($null -eq $Value -or [string]$Value -eq '') { return 'Unknown (missing)' }
    $map = $(if ($Kind -eq 'AddressFamily') { @{ '2'='IPv4'; '23'='IPv6'; 'InterNetwork'='IPv4'; 'InterNetworkV6'='IPv6'; 'IPv4'='IPv4'; 'IPv6'='IPv6' } }
        else { @{ '0'='Disconnected'; '1'='Connected'; 'Disconnected'='Disconnected'; 'Connected'='Connected' } })
    if ($map.ContainsKey([string]$Value)) { return $map[[string]$Value] }
    'Unknown (' + [string]$Value + ')'
}

# Deterministic wrapping avoids Format-Table dropping columns in narrow hosts.
function Split-ConsoleLine {
    param([string]$Text, [int]$Width)
    $clean = $Text -replace '[\x00-\x1f\x7f]', ' '
    if (-not $clean) { return '' }
    for ($offset = 0; $offset -lt $clean.Length; $offset += $Width) {
        $clean.Substring($offset, [Math]::Min($Width, $clean.Length - $offset))
    }
}

function Format-DnsConsoleReport {
    param([object[]]$Checks, [ValidateRange(20,1000)][int]$Width = 80)
    $rows = @(Get-DnsResultSummary $Checks)
    if (-not $rows.Count) { return }
    Split-ConsoleLine 'DNS results: Outcome is the probe result, not collection status.' $Width
    if ($Width -ge 60) {
        $widths = @( [int](($Width - 6) * .32), 5, 9, 0 )
        $widths[3] = $Width - 6 - $widths[0] - $widths[1] - $widths[2]
        $all = @([pscustomobject]@{Server='Server';QueryType='Type';ProbeOutcome='Outcome';Reason='Skip/error reason'}) + $rows
        foreach ($row in $all) {
            $cells = @($row.Server,$row.QueryType,$row.ProbeOutcome,$row.Reason)
            $parts = @(); $height = 1
            for ($c=0; $c -lt 4; $c++) {
                $pieces = @(Split-ConsoleLine ([string]$cells[$c]) $widths[$c])
                $parts += ,$pieces
                $height = [Math]::Max($height,$pieces.Count)
            }
            for ($line=0; $line -lt $height; $line++) {
                $columns = for ($c=0; $c -lt 4; $c++) {
                    $value = $(if ($line -lt $parts[$c].Count) { $parts[$c][$line] } else { '' })
                    $value.PadRight($widths[$c])
                }
                ($columns -join '  ').TrimEnd()
            }
        }
    } else {
        foreach ($row in $rows) {
            foreach ($field in @('Server','QueryType','ProbeOutcome','Reason')) { Split-ConsoleLine ($field + ': ' + $row.$field) $Width }
            ''
        }
    }
    foreach ($group in @($rows | Group-Object ProbeOutcome)) { Split-ConsoleLine ($group.Name + ': ' + $group.Count) $Width }
    Split-ConsoleLine 'Configured associations (not observed query paths), once per target:' $Width
    foreach ($group in @($rows | Group-Object TargetId)) {
        $row = $group.Group[0]
        Split-ConsoleLine ('Server: ' + $row.Server) $Width
        Split-ConsoleLine $row.ConfiguredAssociations $Width
        if ($row.ScopeUncertainty) { Split-ConsoleLine ('Scope: ' + $row.ScopeUncertainty) $Width }
    }
}

function Get-DnsResultSummary {
    param([object[]]$Checks)
    foreach ($check in $Checks) {
        if ($check.Request.Kind -ne 'DNS' -and $check.Name -notlike 'Connectivity:DNS:*') { continue }
        $probe = @($check.Data | Where-Object Kind -eq 'DNS' | Select-Object -First 1)
        $target = $check.Request.DnsTarget
        if ($probe.Count -gt 0 -and $probe[0].DnsTarget) { $target = $probe[0].DnsTarget }
        $p = $(if ($probe.Count) { $probe[0] } else { $null })
        $reason = $(if ($p.Outcome -eq 'Skipped') { $p.SkipReason } elseif ($p.DnsError) {
            $p.DnsError.Classification + ' [' + $p.DnsError.Code + ']: ' + $p.DnsError.Message
        } elseif ($check.Status -ne 'Success') { 'Collection ' + $check.Status + ': ' + $check.Error.Message }
        elseif ($p.Error) { $p.Error.Message } else { '-' })
        [pscustomobject]@{ TargetId = $(if ($target.TargetId) { $target.TargetId } else { $check.Request.Destination })
            Reason = $reason; Server = $(if ($target) { $target.Server } else { $check.Request.Destination })
            ConfiguredAssociations = $(if ($target) { ($target.ConfiguredAssociations | ForEach-Object { 'Interface ' + $_.InterfaceIndex + ' (' + $_.InterfaceAlias + '); adapters: ' + (($_.Adapters | ForEach-Object { $_.Name + '/' + $_.Status + '/' + $_.Kind }) -join ', ') + '; IP states: ' + (($_.IPInterfaceStates | ForEach-Object { (Get-NetworkDisplayLabel AddressFamily $_.AddressFamily) + '/' + (Get-NetworkDisplayLabel ConnectionState $_.ConnectionState) }) -join ', ') }) -join '; ' } else { 'Unavailable' })
            Classification = $target.Classification; SelectionReason = $target.Reason
            ScopeUncertainty = ($target.ScopeUncertainty -join '; ')
            QueryName = $(if ($p -and $p.Evidence.QueryName) { $p.Evidence.QueryName } else { $check.Request.QueryName })
            QueryType = $(if ($p -and $p.Evidence.QueryType) { $p.Evidence.QueryType } else { $check.Request.QueryType })
            CollectionStatus = $check.Status; ProbeOutcome = $(if ($p) { $p.Outcome } else { 'Unknown' })
            DnsErrorClassification = $p.DnsError.Classification; DnsErrorCode = $p.DnsError.Code
            TimeoutScope = $(if ($check.Status -eq 'TimedOut') { 'Worker' } else { $p.TimeoutScope })
            DurationMs = $(if ($p) { $p.DurationMs } else { $check.DurationMs }) }
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
    $dnsRows = @(Get-DnsResultSummary $Evidence.Checks)
    $null = $html.Append('<h2>DNS targets and results</h2><p>Configured associations are not observed query paths. Legacy discovery addresses have unconfirmed operational use; their presence or failure does not establish a DNS fault.</p>')
    $null = $html.Append('<p>Probe outcome counts: ')
    foreach ($outcome in @('Success','Failed','Skipped','TimedOut','Unknown')) {
        $null = $html.Append($outcome + '=' + @($dnsRows | Where-Object ProbeOutcome -eq $outcome).Count + ' ')
    }
    $null = $html.Append('</p><table><tr>')
    $dnsFields = @('Server','ConfiguredAssociations','Classification','SelectionReason','ScopeUncertainty','QueryName','QueryType','CollectionStatus','ProbeOutcome','DnsErrorClassification','DnsErrorCode','TimeoutScope','DurationMs')
    foreach ($field in $dnsFields) { $null = $html.Append('<th>' + $field + '</th>') }
    $null = $html.Append('</tr>')
    foreach ($row in $dnsRows) {
        $null = $html.Append('<tr>')
        foreach ($field in $dnsFields) { $null = $html.Append('<td>' + (& $encode $row.$field) + '</td>') }
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
