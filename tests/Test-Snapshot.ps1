#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\Collection.ps1')
. (Join-Path $root 'src\State.ps1')
. (Join-Path $root 'src\Events.ps1')
$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertions++
}
foreach ($case in @(
    @('169.254.0.0','APIPA'), @('169.254.255.255','APIPA'), @('169.253.255.255','IPv4'),
    @('169.255.0.0','IPv4'), @('192.168.1.20','IPv4'), @('127.0.0.1','IPv4'),
    @('fe80::1','IPv6LinkLocal'), @('fe80::1%12','IPv6LinkLocal'), @('2001:db8::1','IPv6'),
    @('::1','IPv6'), @('not-an-address','Invalid'), @('','Invalid'), @('999.1.1.1','Invalid')
)) {
    Assert-True ((Get-AddressClassification $case[0]) -eq $case[1]) "Classify $($case[0]) as $($case[1])"
}
Assert-True ((Get-AddressClassification $null) -eq 'Invalid') 'Null address'
$checks = @(
    Invoke-DiagnosticCheck 'IPAddresses' { [pscustomobject]@{ IPAddress = '169.254.12.3'; InterfaceIndex = 7 } }
    Invoke-DiagnosticCheck 'Adapters' {
        [pscustomobject]@{ Status = 'Up'; HardwareInterface = $true; InterfaceType = 6 }
        [pscustomobject]@{ Status = 'Up'; HardwareInterface = $true; InterfaceType = 71 }
    }
    Invoke-DiagnosticCheck 'Denied' { throw [UnauthorizedAccessException]::new('Synthetic permission failure') }
    Invoke-DiagnosticCheck 'Missing' { throw [NotSupportedException]::new('Synthetic unavailable check') }
    Invoke-DiagnosticCheck 'MissingCommand' { & 'Nonexistent-NetworkDiagnosticTestCommand' }
    Invoke-DiagnosticCheck 'Failed' { Write-Error 'Synthetic nonterminating error' }
    Invoke-DiagnosticCheck 'AfterFailure' { 'continued' }
)
Assert-True ($checks[2].Status -eq 'PermissionDenied') 'Permission denial is explicit'
Assert-True ($checks[3].Status -eq 'Unavailable') 'Unsupported check is explicit'
Assert-True ($checks[4].Status -eq 'Unavailable') 'Missing command is explicit'
Assert-True ($checks[5].Status -eq 'Failed') 'Nonterminating error is caught'
Assert-True ($checks[6].Data[0] -eq 'continued') 'Collection continues after errors'
$nativeDenied = Invoke-DiagnosticCheck 'WiFi' { throw 'Function WlanQueryInterface returns error 5: The requested operation requires elevation.' }
Assert-True ($nativeDenied.Status -eq 'PermissionDenied') 'Native Wi-Fi permission error is classified'
$partial = Invoke-DiagnosticCheck 'Partial' { 'partial'; throw 'broken' }
Assert-True ($partial.Status -eq 'Failed' -and $partial.Data.Count -eq 0) 'Partial data is not reported as success'
$findings = Get-DiagnosticFindings $checks
Assert-True ($findings.Observations.Count -eq 2) 'APIPA and simultaneous links flagged'
Assert-True ($findings.Hypotheses.Count -eq 2) 'Hypotheses separate from observations'
$virtualChecks = @(Invoke-DiagnosticCheck 'Adapters' {
    [pscustomobject]@{ Status = 'Up'; HardwareInterface = $false; InterfaceType = 6 }
    [pscustomobject]@{ Status = 'Up'; HardwareInterface = $true; InterfaceType = 71 }
})
Assert-True ((Get-DiagnosticFindings $virtualChecks).Observations.Count -eq 0) 'Virtual Ethernet does not trigger physical dual-link flag'
$downChecks = @(Invoke-DiagnosticCheck 'Adapters' {
    [pscustomobject]@{ Status = 'Up'; HardwareInterface = $true; InterfaceType = 6 }
    [pscustomobject]@{ Status = 'Disconnected'; HardwareInterface = $true; InterfaceType = 71 }
})
Assert-True ((Get-DiagnosticFindings $downChecks).Observations.Count -eq 0) 'Disconnected Wi-Fi does not trigger dual-link flag'
Assert-True ((Get-DiagnosticFindings @()).Observations.Count -eq 0) 'Empty checks produce no fabricated observations'
$payload = '<script>alert("test")</script><img src=x onerror=alert(1)>&'
$unicode = [string][char]0x00E9 + [char]0x03A9
$reportChecks = @(
    [pscustomobject]@{ Name = $payload; Status = $payload; Data = @($payload, $unicode); Error = $null }
    [pscustomobject]@{ Name = 'Denied'; Status = 'PermissionDenied'; Data = @(); Error = [pscustomobject]@{ Message = $payload } }
)
$evidence = [pscustomobject]@{
    SchemaVersion = 1; CollectedAt = $payload; Checks = $reportChecks
    Findings = [pscustomobject]@{ Observations = @($payload); Hypotheses = @($payload) }
}
$testDir = Join-Path $root ('output\tests-' + [guid]::NewGuid().ToString('N'))
$paths = Write-DiagnosticReport $evidence $testDir
$roundtrip = Get-Content -LiteralPath $paths.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$html = Get-Content -LiteralPath $paths.HtmlPath -Raw -Encoding UTF8
Assert-True ($roundtrip.Checks[0].Data[0] -ceq $payload) 'JSON preserves evidence without HTML mutation'
Assert-True ($roundtrip.Checks[0].Data[1] -ceq $unicode) 'UTF-8 evidence survives round trip'
Assert-True ($roundtrip.Checks[1].Status -eq 'PermissionDenied') 'JSON records failed check status'
Assert-True ($html -notmatch '<script>|<img') 'No injected HTML elements'
Assert-True ($html.Contains([Net.WebUtility]::HtmlEncode($payload))) 'Hostile strings HTML encoded'
Assert-True ($html.Contains('&amp;')) 'Ampersands encoded'
Assert-True ($html.Contains('<h2>Observations</h2>') -and $html.Contains('<h2>Hypotheses</h2>')) 'Separate report sections'
Assert-True ($html.Contains('PermissionDenied')) 'Report surfaces failed checks'
$empty = [pscustomobject]@{ CollectedAt = 'synthetic'; Checks = @(); Findings = Get-DiagnosticFindings @() }
$emptyPaths = Write-DiagnosticReport $empty (Join-Path $testDir 'empty')
Assert-True ((Get-Content $emptyPaths.HtmlPath -Raw).Contains('None recorded. Missing checks may limit findings.')) 'Empty reports explain limitations'
# Stub event commands to exercise query bounds without depending on local log contents.
function Get-WinEvent {
    [CmdletBinding(DefaultParameterSetName='Query')]
    param([Parameter(ParameterSetName='List')][string]$ListLog,
        [Parameter(ParameterSetName='Query')][hashtable]$FilterHashtable,
        [Parameter(ParameterSetName='Query')][int]$MaxEvents)
    if ($PSCmdlet.ParameterSetName -eq 'List') { return [pscustomobject]@{ IsEnabled = ($ListLog -ne 'Disabled'); ProviderNames = @('Synthetic') } }
    $script:seenFilter = $FilterHashtable
    $script:seenLimit = $MaxEvents
    if ($FilterHashtable.LogName -eq 'Empty') {
        Write-Error -Message 'No events' -ErrorId 'NoMatchingEventsFound' -Category ObjectNotFound
    } else {
        1..$MaxEvents | ForEach-Object {
            $event = [pscustomobject]@{ Id = $_; Message = 'Synthetic event'; TimeCreated = [datetime]'2026-01-01T00:01:00' }
            $event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { '<Event><EventData><Data Name="Detail">raw &amp; structured</Data></EventData></Event>' }
            $event
        }
    }
}
$start = [datetime]'2026-01-01T00:00:00'
$end = $start.AddHours(2)
$events = Get-RecentNetworkEvents -LogName 'System' -StartTime $start -EndTime $end -MaxEvents 3 -Providers @('Synthetic')
Assert-True ($script:seenFilter.StartTime -eq $start -and $script:seenFilter.EndTime -eq $end) 'Event time bounds passed to Windows filter'
Assert-True ($script:seenLimit -eq 3 -and $events.Events.Count -eq 3 -and $events.LimitReached) 'Event count cap and limit indicator'
Assert-True ($script:seenFilter.ProviderName[0] -eq 'Synthetic') 'System provider filter retained'
Assert-True ($events.Events[0].Xml -like '*<EventData>*raw &amp; structured*') 'Structured event XML preserved'
$unsupported = Get-RecentNetworkEvents -LogName 'System' -StartTime $start -EndTime $end -MaxEvents 3 -Providers @('MissingProvider')
Assert-True ($unsupported.QueryStatus -eq 'Unavailable' -and $unsupported.Providers[0].Status -eq 'Unavailable' -and $unsupported.Events.Count -eq 0) 'Unsupported providers are explicit, never an unfiltered query'
$emptyEvents = Get-RecentNetworkEvents -LogName 'Empty' -StartTime $start -EndTime $end -MaxEvents 3 -Providers @()
Assert-True ($emptyEvents.Events.Count -eq 0 -and -not $emptyEvents.LimitReached) 'No matching events is successful empty evidence'
$disabled = Invoke-DiagnosticCheck 'DisabledLog' { Get-RecentNetworkEvents -LogName 'Disabled' -StartTime $start -EndTime $end -MaxEvents 3 -Providers @() }
Assert-True ($disabled.Status -eq 'Unavailable') 'Disabled log explicitly unavailable'
Write-Host "PASS: $script:assertions assertions on PowerShell $($PSVersionTable.PSVersion). Synthetic artifacts: $testDir"
