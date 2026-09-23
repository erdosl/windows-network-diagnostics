# Windows network diagnostics

Milestone 2 review update (`0.2.1`) collects bounded Windows 10/11 network snapshots for
intermittent DHCP, duplicate-IP, DNS, gateway, Ethernet, and Wi-Fi investigations.
It uses Windows PowerShell 5.1, built-in Windows commands, and .NET only.

## Run a passive snapshot

From the repository directory:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
```

Or use an absolute script path from any working directory. Quote paths containing
spaces. No installation or downloaded dependencies are needed. The parent compiles
`src/NativeProcess.cs` using built-in `Add-Type` to supervise worker processes.

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 6 -MaxEventsPerLog 100 -MaxNicEvents 100 -MaxPowerEvents 50 -CheckTimeoutSeconds 30
```

Run as a normal user first. Inaccessible checks are recorded rather than requiring
administration. An administrator can choose to run the same command elevated.
If policy blocks scripts or organizational controls block native compilation,
use your approved execution/signing process. Never bypass execution restrictions.
The collector never changes execution policy, adapters, network settings, leases,
or event-log configuration, and never exports Wi-Fi keys or requests credentials.

## Opt-in connectivity tests

**No active probes run without `-IncludeConnectivityTests`.** Enabling it sends
DNS queries, TCP connections, and HTTPS HEAD requests. Gateway neighbour inspection
is included; gateway ICMP additionally requires `-IncludeGatewayPing`.

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncludeConnectivityTests -IncludeGatewayPing -TcpDestinations 1.1.1.1 -TcpPort 443 -DnsQueryName example.com -HttpsEndpoint https://example.com/ -ProbeTimeoutSeconds 10
```

To pass multiple TCP destinations, invoke the script directly inside Windows
PowerShell (its native `-File` command-line parser does not reliably pass arrays):

```powershell
.\Collect-NetworkDiagnostics.ps1 -IncludeConnectivityTests -TcpDestinations @('1.1.1.1','2606:4700:4700::1111')
```

Default targets, used only after opt-in, are TCP port 443 on `1.1.1.1` and
`2606:4700:4700::1111`, A/AAAA queries for `example.com` against each distinct
configured DNS server, and `https://example.com/`. Hostnames are resolved and TCP/
HTTPS results are collected separately for each returned IPv4/IPv6 address.
Names may be disclosed to DNS infrastructure and destination services. Do not
supply secrets in destinations. HTTPS endpoints reject user information, query
strings, and fragments; credentials, client certificates, cookies, response bodies,
and response authentication headers are not collected or sent.

HTTPS uses a direct TCP/TLS connection with normal certificate validation and an
HTTP/1.1 HEAD request. It does not use configured proxies, follow redirects, or
alter machine TLS settings. HTTP error status lines are retained as `HttpError`;
HEAD rejection is not proof of a network failure. Only the first HTTP response
status line is collected (bounded to 4096 characters).

## Parameters

| Parameter | Default | Bounds / meaning |
| --- | --- | --- |
| `LookbackHours` | 24 | 1-168; event history ending at collection start |
| `MaxEventsPerLog` | 200 | 1-1000; System network group and each dedicated log |
| `MaxNicEvents` | 200 | 1-1000; independent System NIC group |
| `MaxPowerEvents` | 100 | 1-1000; independent System power group |
| `CheckTimeoutSeconds` | 30 | 1-600; deadline per isolated check, including worker startup |
| `IncludeConnectivityTests` | off | Explicit permission for active probes |
| `IncludeGatewayPing` | off | Requires connectivity switch; optional ICMP |
| `TcpDestinations` | two literals above | 1-16 hostnames or IP literals |
| `TcpPort` | 443 | 1-65535 |
| `DnsQueryName` | example.com | A and AAAA queried independently |
| `HttpsEndpoint` | https://example.com/ | HTTPS endpoint without credentials/query/fragment |
| `ProbeTimeoutSeconds` | 10 | 1-60; shared elapsed-time probe budget, starting inside the worker |
| `ProbeWorkerOverheadSeconds` | 15 | 5-120; additional worker startup/setup/result-writing allowance |

Each check runs in a fresh `powershell.exe -NoProfile -NonInteractive -File`
worker, with explicit serialized inputs. A Windows Job Object owns the worker
and descendants, including native commands. Deadline or parent termination kills
the process tree. Workers write only private scratch results; only the parent
writes evidence/HTML. Cleanup can add up to five seconds beyond a check deadline.
Passive checks use `CheckTimeoutSeconds`. Active checks use an independent hard
worker budget of `ProbeTimeoutSeconds + ProbeWorkerOverheadSeconds` (25 seconds
by default), not capped by the passive check timeout. The additional allowance
leaves bounded time for process startup, imports and result serialization. It is
not extra network-operation time. An unusually slow startup or blocked provider
can still exhaust the hard worker deadline.

The probe stopwatch starts inside the loaded worker. Route/source lookup and all
network stages consume that one budget. TCP connect, TLS negotiation, HTTP request
writing and every status-line read use only the remaining milliseconds. Slow HTTP
bytes cannot renew the deadline. Hostname resolution is awaited with the remaining
budget. Synchronous Windows route/neighbour/interface and `Resolve-DnsName`
providers cannot always be interrupted cooperatively: the elapsed budget is
checked when they return, and the hard worker kill remains the fallback if they
stall. DNS uses Windows' `-QuickTimeout`; its OS timeout can differ from the probe
budget. A hard worker timeout is not evidence of a network timeout.
There is no total snapshot deadline; checks are sequential, not simultaneous.

## Evidence and reports

Paths are independent of the caller's working directory:

```text
<repository>/output/snapshot-<ComputerName>-<RunId>/evidence.json
<repository>/output/snapshot-<ComputerName>-<RunId>/summary.html
```

Open the printed HTML path in a browser. All dynamic values are HTML-encoded;
there are no scripts or external resources. The interface section joins sources
by index, retains all addresses and default routes, shows family-specific metrics,
and reports unavailable sources. It does not choose an "active gateway" from
configuration. Raw check evidence remains below the summaries and in JSON.

Schema **3** retains the schema 2 identity/state fields: `ComputerName`, GUID `RunId`, `CollectorVersion`, `IsElevated`,
`StartedAt`/`CompletedAt` with offsets, `CollectionStatus`, `Revision`, `PendingCheck`,
`PlannedChecks`, `Parameters`, and `CollectionError`. `CollectedAt` remains an alias
for start time. Parameters formerly at the root now live under `Parameters`.
Checks include their name, request arguments, start/end, duration, deadline,
worker PID, status, data, and error details. `PlannedChecks` expands as work is
scheduled (including target resolution); it is not a fixed upfront list.

A directory and `Incomplete` checkpoint are created before collection. The parent
saves before starting and after finishing each check, using flushed temporary
files and atomic replacement with `.bak` recovery copies. Brief file-sharing
conflicts are retried for up to 1.8 seconds; unsafe delete-then-move is never used.
JSON is authoritative; HTML can lag by one revision if interrupted between writes.
The two files are not an atomic pair. Old HTML identifies its revision and may
show an older incomplete state. A hard interruption leaves the last checkpoint
`Incomplete`, with no completion timestamp and the pending check where known.

`Complete` means all scheduled checks were attempted, not that they succeeded.
Statuses are `Success`, `Failed`, `Unavailable`, `PermissionDenied`, `TimedOut`,
and `Skipped`. The console and HTML check summary show **CollectionStatus** (the raw check's
`Status`) separately from **ProbeOutcome** (each raw `Data[].Outcome`). For example,
`CollectionStatus=Success, ProbeOutcome=Failed` means the failed test was recorded
successfully; it does not mean connectivity worked. `HttpError` preserves HTTP
error responses separately from TCP/TLS failures. Gateway `Observed` means only
neighbour evidence was inspected, without ICMP.

Schema 3 adds `Parameters.ProbeWorkerOverheadSeconds`, per-check `TimeoutScope`
(`Worker` for forced termination), and per-probe `ProbeTimeoutMs`, `TimeoutScope`
(`Probe` for ordinary budget/network timeouts) and `CompletedStages`. Existing raw
`Status`, `Outcome`, errors, endpoints and evidence remain available. A normal
probe timeout can have collection status `Success` and retains completed TCP/TLS
stages and observed endpoints. A worker timeout instead shows collection status
`TimedOut`, probe outcome `Unknown (no completed result)`, and scope `Worker`.
A killed probe retains destination/options in `Request`; unfinished worker data
is not presented as completed evidence. Report-write errors fail the command.

To inspect/recover evidence in a policy-permitted Windows PowerShell session:

```powershell
. .\src\State.ps1
$evidence = Read-DiagnosticEvidence -Path 'C:\path\to\output\snapshot-computer-runid\evidence.json'
```

A corrupt/unreadable primary falls back to `.bak`, marked `Incomplete` with a
`RecoveryNote`. Recovery does not resume collection or silently mark it complete.
Backup files and temporary/scratch leftovers are also private diagnostic output.

## Collection scope and interpretation

- Windows version/time zone; all Windows-exposed adapters including hidden ones,
  MACs, status, link speed, NIC driver details and driver service names.
- Per-interface IPv4/IPv6 addressing, prefixes/states, DHCP configuration/server/
  lease times where available, gateways, DNS, routes, metrics, and neighbours.
- Connection-only `netsh wlan show interfaces`; no profile or key export.
- Separate System network (DHCP/TCP-IP/DNS), NIC (NDIS/Kernel-PnP plus discovered
  NIC service names), and power (sleep/wake/boot/power transitions) queries.
  DHCP Admin/Operational and WLAN/Wired AutoConfig logs have their own caps.
  Each event retains readable text and XML. Unsupported providers are listed;
  disabled/inaccessible logs are explicit and are never enabled. `LimitReached`
  indicates older matching events may have been omitted. `QueryStatus` can be
  unavailable even when a worker successfully reports provider availability.
- Optional probes retain destination, address family, request, timing, outcome,
  errors, and route predictions. TCP/HTTPS additionally retain actual local/remote
  socket endpoints when a connection was established, even if TLS later fails.
  Matching interfaces are derived from the observed local address; ambiguous
  matches are retained. DNS/ICMP source interfaces are not observed. No test is
  labelled Ethernet/Wi-Fi based only on a predicted route or configured gateway.

Observations and hypotheses remain separate. APIPA and simultaneous physical
Ethernet/Wi-Fi links are flags, not diagnoses. IPv6 link-local is not APIPA.
No ping reply does not prove unreachability; one failed DNS query does not prove
DNS is the cause. A snapshot cannot prove an intermittent fault or duplicate IP.

## Tests and validation

Run these actual files using Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1
```

They are dependency-free. Tests use synthetic data/mocked collectors, real local
worker timeouts/child cleanup, and loopback-only socket failures. They never
probe an external network. Artifacts remain under ignored `output/` directories.
See [validation results](docs/VALIDATION.md) for the actual environment, commands,
results, file-execution validation, and remaining unverified coverage.

## Privacy, limitations, and deferred work

Keep all generated artifacts under ignored `output/`. Addresses, MACs, SSIDs,
computer names, event XML/messages, and connection endpoints are sensitive.
Windows event contents are not redacted. Review before sharing. Ignore rules
cannot detect credentials embedded in source or untrack previously added files.

Collection is sequential and reflects changing state. Driver/event availability
varies; discovered NIC service names need not match registered event providers,
so vendor event coverage is best effort, not exhaustive. DHCP lease fields are
primarily IPv4. Localized Wi-Fi output and Windows permissions/location settings
may limit checks. A constrained or policy-blocked worker is reported as failure,
not bypassed. Atomic file replacement requires a filesystem that supports it.

Continuous monitoring, subnet scanning, Nmap, vendor lookup, packet capture, and
Eero/UniFi integrations are out of scope. See [LICENSE](LICENSE).
