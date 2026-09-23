# Windows network diagnostics

Milestone 1 is a read-only Windows 10/11 snapshot collector for investigating
intermittent DHCP, duplicate-IP, DNS, gateway, and Ethernet/Wi-Fi problems.
It requires Windows PowerShell 5.1 and built-in Windows commands only.

## Usage

Open Windows PowerShell in the repository directory:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
```

To collect up to 100 events per selected log over the preceding six hours:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 6 -MaxEventsPerLog 100
```

`LookbackHours` accepts 1-168 (default 24). `MaxEventsPerLog` accepts 1-1000
(default 200). Run as a normal user first. Restricted checks are recorded in the
report; an administrator may choose to run from an elevated PowerShell window
for additional access. If execution policy blocks script files, use your
organization's approved execution/signing process. The collector never changes
execution policy, network settings, adapters, leases, or event-log configuration.
It performs no active probes and never requests credentials or exports Wi-Fi keys.

Each run prints paths to a unique directory under the repository:

```text
output/snapshot-<timestamp>-<id>/evidence.json
output/snapshot-<timestamp>-<id>/summary.html
```

Open the printed HTML path in a browser. The summary is self-contained, with no
scripts or external resources. All dynamic content is HTML-encoded. JSON preserves
evidence, schema version, capture timestamps, parameters, and check results.

Individual check failures do not prevent later checks or report generation.
Check statuses are `Success`, `Unavailable`, `PermissionDenied`, or `Failed`, with
error details. A successful command exit does not mean all checks succeeded.
Fatal setup or report-write errors fail the command.

## Evidence collected

- Windows version/build, timestamps with UTC offset, and Windows time zone.
- All Windows-exposed adapters including hidden adapters, MACs, status, link speed,
  interface types, hardware flags, and driver details; separate signed NIC drivers
  include device IDs for correlation.
- Per-interface IPv4/IPv6 addresses and prefixes, address origins/states, DHCP
  settings/server/lease times where WMI exposes them, gateways, DNS servers, and
  DNS suffixes. Interface indices and device IDs support correlation.
- Routes, interface metrics, and IPv4/IPv6 neighbour cache entries.
- Localized `netsh wlan show interfaces` output only, never profile/key export.
- Recent System DHCP, TCP/IP, NDIS, DNS Client, and Kernel-PnP events, plus DHCP
  Admin/Operational and WLAN/Wired AutoConfig Operational logs. Queries are bounded
  by capture-time window and per-log count, newest first. `LimitReached` means
  older matching events may have been omitted. Empty results differ from failures.
  Disabled logs are recorded as unavailable and are never enabled.

APIPA (`169.254.0.0/16`) and simultaneously up physical Ethernet/Wi-Fi adapters
are observations, not proven root causes. Dual-link detection uses interface types
6 and 71 and hardware flags, not localized names. IPv6 link-local is not APIPA.
Hypotheses appear in a separate section. Missing checks limit conclusions.

## Tests

Run the dependency-free synthetic suite:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
```

Tests cover APIPA boundaries, IPv4/IPv6 and invalid addresses, dual-link flags,
failure isolation, permission/unavailable statuses, JSON round trips, UTF-8, HTML
injection escaping, empty reports, and event query bounds using stub commands.
Synthetic artifacts remain in ignored `output/tests-<id>/` for inspection.

See [validation results](docs/VALIDATION.md) for the exact tested environment,
results, and this host's file-execution-policy limitation.

## Privacy and Git

Keep generated diagnostics in `output/`, which is ignored by Git. Other report
and capture directories, logs, trace files, archives, credentials, keys, and local
configuration are also excluded. Ignore rules cannot detect embedded secrets or
untrack files already in Git. Commit only reviewed source and documentation.

Reports contain sensitive metadata: addresses, MACs, SSIDs, and Windows event
messages. Event messages are not automatically redacted; review before sharing.

## Limitations and deferred work

A single snapshot cannot prove an intermittent outage, address conflict, DNS
failure, or gateway fault. Collection is sequential, not an atomic view of state.
There is no per-command timeout; stalled Windows management services may delay
completion. Available fields depend on Windows and driver support. WMI DHCP
lease fields primarily describe IPv4; full DHCPv6 leases are not promised.
Wi-Fi output is localized and may be restricted by permissions/location settings.
Vendor-specific link-event providers are not exhaustively covered. Disabled logs
and missing historical events cannot be recovered by this collector.

Monitoring, subnet scanning, Nmap, vendor lookup, and packet capture are deferred.
There is no Eero or UniFi management integration.

See [LICENSE](LICENSE).
