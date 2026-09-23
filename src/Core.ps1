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

function Write-DiagnosticReport {
    param([Parameter(Mandatory)]$Evidence, [Parameter(Mandatory)][string]$OutputDirectory)
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop
    $json = ConvertTo-Json -InputObject $Evidence -Depth 16
    $jsonPath = Join-Path $OutputDirectory 'evidence.json'
    $htmlPath = Join-Path $OutputDirectory 'summary.html'
    $encode = { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
    $html = [System.Text.StringBuilder]::new()
    $null = $html.Append('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Network snapshot</title><style>body{font:16px system-ui;margin:2rem;max-width:1000px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f4f6;padding:1rem}li{margin:.5rem 0}</style></head><body><h1>Network snapshot</h1>')
    $null = $html.Append('<p>Collected: ' + (& $encode $Evidence.CollectedAt) + '</p><p>Read-only evidence. A snapshot does not establish a root cause or prove connectivity.</p>')
    foreach ($section in @('Observations', 'Hypotheses')) {
        $null = $html.Append('<h2>' + $section + '</h2><ul>')
        $items = @($Evidence.Findings.$section)
        if ($items.Count -eq 0) { $null = $html.Append('<li>None recorded. Missing checks may limit findings.</li>') }
        foreach ($item in $items) { $null = $html.Append('<li>' + (& $encode $item) + '</li>') }
        $null = $html.Append('</ul>')
    }
    $null = $html.Append('<h2>Checks and evidence</h2>')
    foreach ($check in $Evidence.Checks) {
        $null = $html.Append('<h3>' + (& $encode $check.Name) + ': ' + (& $encode $check.Status) + '</h3><pre>')
        $detail = ConvertTo-Json -InputObject $check -Depth 14
        $null = $html.Append((& $encode $detail) + '</pre>')
    }
    $null = $html.Append('</body></html>')
    # Explicit UTF-8 works on Windows PowerShell 5.1 and does not depend on console encoding.
    [IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($htmlPath, $html.ToString(), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ JsonPath = $jsonPath; HtmlPath = $htmlPath }
}
