# Milestone 1 validation

Validated on 2026-09-23 on Windows 10 Pro, build 19045, using
`powershell.exe` version 5.1.19041.7725. No execution policy or network settings
were changed. No commit or push was performed.

## Results

- All four `.ps1` files parsed with the Windows PowerShell 5.1 AST parser.
- 40 synthetic assertions passed: APIPA boundaries; IPv4, IPv6, IPv6 link-local,
  null and invalid addresses; APIPA/physical dual-link observations; virtual and
  disconnected adapter exclusions; failure isolation; unavailable commands/checks;
  permission and native Wi-Fi elevation errors; JSON/UTF-8 round trips; HTML
  encoding of hostile names, statuses, timestamps, data, errors, observations,
  and hypotheses; empty reports; bounded event queries and disabled/empty logs.
- A sandboxed live snapshot continued despite ten permission-denied checks.
  Five checks succeeded and one disabled event log was unavailable. The report
  preserved these outcomes. This run exposed and verified a fix for Windows
  networking module errors that require explicit `-ErrorAction Stop`.
- A live snapshot outside the sandbox, with a six-hour lookback and 100-event
  per-log cap, completed with 15 successful checks and one unavailable check.
  The DHCP Client Operational log was disabled and was left disabled.
- That live snapshot contained 26 adapters, 23 driver records, 27 addresses,
  25 adapter configuration records, 28 DNS records, 27 IP interfaces, 97 routes,
  and 161 neighbours. Wi-Fi connection and four event-log queries succeeded.
  A successful event query may return no matching events.
- Parsed the live JSON in Windows PowerShell 5.1: verified 16 checks, populated
  adapter interface types, event counts no greater than 100, and event timestamps
  within the requested interval. Checked that HTML includes unavailable status
  and contains no script or iframe elements. Synthetic tests exercise encoding;
  no browser rendering review was performed.
- `git diff --check` passed. `git check-ignore` verified JSON, HTML, and synthetic
  output paths are ignored. `git ls-files output` returned no tracked output.

## Execution-policy limitation and inline validation

The documented `powershell.exe -NoProfile -File` commands for the collector and
test suite were attempted both inside and outside the sandbox. Both were blocked
by this host's default script execution policy. All policy scopes were Undefined
before and after validation. No `Set-ExecutionPolicy`, execution-policy override,
or file unblocking was used.

For runtime validation, source text was passed as inline `-Command` input to
Windows PowerShell 5.1. Supporting functions were prepended instead of dot-sourced,
and the repository working directory replaced script-root resolution. Consequently,
normal file launch and dot-sourcing were parsed but not validated end to end here.
The following reproduces the synthetic inline run from the repository directory:

```powershell
$core = Get-Content .\src\Core.ps1 -Raw
$collection = Get-Content .\src\Collection.ps1 -Raw
$test = Get-Content .\tests\Test-Snapshot.ps1 -Raw
$test = $test -replace '(?m)^\$root = Split-Path \$PSScriptRoot -Parent', '$root = (Get-Location).Path'
$test = $test -replace '(?m)^\. \(Join-Path \$root .+\)\r?\n', ''
& powershell.exe -NoProfile -Command ($core + "`n" + $collection + "`n" + $test)
```

The live run used the same supporting source text with the entry point in a script
block, preserving its parameter declarations:

```powershell
$entry = Get-Content .\Collect-NetworkDiagnostics.ps1 -Raw
$entry = $entry -replace '(?m)^\. \(Join-Path \$PSScriptRoot .+\)\r?\n', ''
$inline = $core + "`n" + $collection + "`n& {`n" + $entry.Replace('$PSScriptRoot', '(Get-Location).Path') + "`n} -LookbackHours 6 -MaxEventsPerLog 100"
& powershell.exe -NoProfile -Command $inline
```

## Remaining coverage limits

Windows 11, other locales, full DHCPv6 leases, actual DHCP outages/address conflicts,
and simultaneous physical Ethernet/Wi-Fi links were not exercised live. Dual-link
and APIPA logic were covered with synthetic data. Unavailable/disabled checks,
permissions, driver-dependent fields, and sequential collection limit inference.
Per-command timeouts, active connectivity tests, and the deferred milestones are
not implemented. See the README for collection scope and known limitations.
