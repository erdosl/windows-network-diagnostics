# Windows network diagnostics

Milestone 3 (`0.3.1`) collects bounded Windows 10/11 network snapshots for
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

## Passive logical network map

Every checkpoint includes a logical model derived only from completed successful
snapshot checks. It shows the collecting computer, interface-scoped addresses and
prefix-derived subnets, candidate routes/default gateways, neighbour-cache
observations, and any existing probe route predictions/socket endpoints. It adds
no network discovery traffic. This is **not a physical wiring diagram**. Switches,
ports, cables and access-point paths remain unknown. Localized Wi-Fi output stays
raw; structured association is explicitly unavailable rather than guessed.

HTML groups interface/subnet/gateway evidence and provides collapsible neighbour
lists grouped by interface, with source references, collection intervals and
plain-language limitations. The console gives interface/subnet and neighbour
observation counts plus coverage gaps. Counts are not verified physical devices.
Same IPs or MACs on different interfaces are never merged into devices; IPv6 zones
and overlapping interface prefixes stay separate. Repeated observations can have
several explanations (including proxying or conflicts); no duplicate-IP fault is
inferred. Configured routes do not prove reachability or active route selection,
and even a Reachable cache state is only a historical snapshot.

The endpoint-observation count excludes multicast, limited IPv4 broadcast,
directed broadcast derived from known same-interface address prefixes, invalid or
unspecified IPs, and missing/zero/multicast/non-Ethernet MAC values. /31 and /32 do
not imply broadcast endpoints. All observations remain in JSON/raw evidence.
MAC eligibility is conservative, not a device identity or a reachability test.
Remote socket destinations are never identified using a gateway's MAC.

Two new passive check families run separately **for each inventoried adapter**:
`AdapterStatistics:<index>` and `AdapterPowerManagement:<index>`. Each has its
own `CheckTimeoutSeconds` worker budget, explicit name/index/GUID arguments,
request/error evidence and timestamps. Supported provider properties are retained
in `Data[].Fields`; CIM/PowerShell transport metadata is excluded. A failed or
unsupported adapter does not discard other adapters' data. If adapter inventory
is unavailable/empty, both families are marked unavailable. Total run time grows
with adapter count because collection remains sequential. Adapters can change
between inventory and name-based provider reads; identity is not an atomic view.
Counters are cumulative samples, not rates or evidence of a current fault; power
settings are read only and never changed.

Provider references: [adapter statistics](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterstatistics),
[power management](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterpowermanagement),
[neighbour states](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/nettcpipprov/msft-netneighbor).

### Logical model schema

Evidence schema 5 added `LogicalNetwork` with `ModelVersion=1`, `View`, `Nodes`,
`Relationships`, `Coverage`, `Counts` and `Filtering`; original checks remain intact.
Nodes contain `Id`, `Kind`, `InterfaceIndex`, `Label`, `Data` and `Support`.
Relationships contain `Id`, `From`, `To`, `Kind` and `Support`. Every support record
has `CheckName`, `EvidenceReference` (JSON-pointer-style path into this evidence),
`StartedAt`, `CompletedAt`, `EvidenceType` (configured/observed/predicted/inferred)
and `Limitation`. `SnapshotIdentity` denotes collection metadata, using
`/ComputerName`, rather than a separate worker check. Missing historical timestamps
remain null; current checks use their collection interval, not an invented time.

Node IDs are deterministic within the same snapshot: interface index IDs,
interface/prefix/zone subnet IDs, and check/data-index observation IDs. They are
not cross-run device identities. Subnets derive from address prefixes and do not
establish a physical segment. Multiple supports are retained for shared prefixes. Gateways from adapter
configuration remain available even without route data; separate gateway nodes
can reflect duplicate configuration evidence, not additional devices.
Neighbour data includes `StateRaw`, readable `StateLabel` (unknown values explicit),
`Eligibility` and `IncludedInEndpointObservationCount`. All enum/provider values
remain in raw checks. Coverage reports missing/failed/unavailable checks plus
unknown Layer 2 and unavailable structured Wi-Fi relationships. Model generation
is repeated at each saved checkpoint; incomplete snapshot limitations still apply.

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
`2606:4700:4700::1111`, A/AAAA queries for `example.com` against each selected
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

## DNS target selection and interpretation

All configured DNS addresses remain unchanged in raw inventory and interface
summaries. Only the exact parsed IPv6 values `fec0:0:0:ffff::1`, `::2` and `::3`
(with the same `fec0:0:0:ffff` prefix) are classified as legacy DNS discovery
addresses. Equivalent expanded/compressed spellings and scope suffixes are
recognized; other fec0 addresses are not treated as legacy targets.

During opt-in connectivity collection, legacy A/AAAA targets get explicit
`Skipped` check/result records with reason: "Legacy DNS discovery address;
operational use unconfirmed." To probe them, add **both**
`-IncludeConnectivityTests -IncludeLegacyDnsTargets`. The legacy switch alone
is rejected before collection. Their presence or failure does not establish a
DNS fault. Virtual/VPN/disconnected adapters and lack of a default route do not
exclude other configured DNS servers.

Equivalent targets retain all original spellings, scope suffixes, configured
interface indices/aliases, adapter status/kind and family-specific IP-interface
connection state. Explicit IPv6 zones remain separate. Unzoned link/site-local
nonlegacy targets are kept separate by configured interface and marked uncertain;
no interface zone is silently substituted. Unzoned legacy values aggregate all
associations, retaining scope uncertainty. An explicit zone that differs from a
configured interface is preserved and flagged. These are configured associations,
not proof of the query's path; route predictions remain separate from observations.

Schema 4 adds `Parameters.IncludeLegacyDnsTargets`, `Request.DnsTarget` and
`Data[].DnsTarget`, and structured `Data[].DnsError`. Targets contain `TargetId`,
`Server`/`NormalizedAddress`, `OriginalAddresses`, `ScopeId`, `AddressFamily`,
`Classification`, `Selection`, `Reason`, `ScopeUncertainty`,
`ConfiguredAssociations` and `Attribution`. Each association also retains its
original address/scope. Skips have no duration or network result. If a worker is
killed, the request still preserves target associations and query details.

Console results use a compact Server/Type/Outcome/Skip-or-error-reason table.
Long values wrap without ellipses; terminals narrower than 60 columns use labeled
records so essential results are not dropped. Configured interface associations
are shown separately once per target. Address families display IPv4/IPv6 and IP
connection states display Disconnected/Connected; unknown values are explicit.
These are presentation labels only: raw numeric values remain unchanged in JSON.
The mappings follow [MSFT_NetIPInterface](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/FWP/wmi/nettcpipprov/msft-netipinterface.md).
HTML includes the detailed DNS table; both outputs include separate outcome counts.
DNS errors preserve message, FullyQualifiedErrorId, category, exception type and
numeric-code sources. Native Win32 codes and Win32-facility HRESULTs map 1460 and
10060 to Timeout, 9003 to NameError/NXDOMAIN, 9002 to ServerFailure, and 9005 to
Refused. Unrecognized/missing/conflicting codes remain Unknown. Message language,
error-ID text and empty answers do not determine classification. A recognized
DNS timeout has ProbeOutcome TimedOut and TimeoutScope DNS; a cooperative elapsed
budget has scope Probe; a killed worker has scope Worker and unknown probe outcome.
None alone proves unreachability or a DNS root cause.

Code references: [Microsoft DNS error codes](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--9000-11999-),
[Win32 timeout](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-),
[Winsock error codes](https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2).

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
| `IncludeLegacyDnsTargets` | off | Requires connectivity switch; probe exact legacy discovery targets instead of recording Skipped |
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

Schema **6** retains the schema 2 identity/state fields: `ComputerName`, GUID `RunId`, `CollectorVersion`, `IsElevated`,
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

Schema 3 added `Parameters.ProbeWorkerOverheadSeconds`, per-check `TimeoutScope`
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
powershell.exe -NoProfile -File .\tests\Test-Dns.ps1
powershell.exe -NoProfile -File .\tests\Test-Presentation.ps1
powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1
```

They are dependency-free. Tests use synthetic data/mocked collectors, real local
worker timeouts/child cleanup, and loopback-only socket failures. They never
probe an external network. New synthetic artifacts, orchestration snapshots and corrupt recovery fixtures remain
under ignored `output/tests/` directories. Existing user reports are not moved or deleted.
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

## Adapter availability and APIPA context (0.3.1 / schema 6)

Adapter providers are queried with `-Name '*' -IncludeHidden`, then selected by
ordinal case-insensitive literal name. Wildcard characters in an adapter alias do
not become query patterns. Returned index/GUID fields, where present, must match
the inventoried identity; mismatches are Failed, not classified as absent hardware.
This replaces escaped name-pattern targeting. Provider enumeration remains bounded
per adapter, but can cost more on hosts with many adapters. Missing returned
identity fields and adapters changing during collection limit attribution.

Only the adapter-provider call path recognizes ObjectNotFound with the exact
provider-specific CmdletizationQuery_NotFound_Name ID (or an empty literal match)
as Unavailable: "No matching adapter-provider object was returned." When inventory
enumeration succeeds but literal matching finds no object, the collector generates
an ErrorRecord with ID `AdapterProviderObjectMissing` and category ObjectNotFound;
there is no native provider exception to preserve. When a provider command throws,
its original message, ID, category and exception type are retained alongside the
classification and any Error.Explanation. Error.AdapterIdentity retains the request
identity in both cases. This is not a declaration of faulty or unsupported hardware.
PermissionDenied, unexpected Failed and worker TimedOut remain distinct. Unrelated
ObjectNotFound errors are not changed. Console, HTML and map coverage use the same
check status; previously generated reports are not relabelled.

Schema 6 adds Findings.ApipaDetails while retaining Observations/Hypotheses as
string arrays for existing consumers. Every APIPA address has interface identity,
adapter description/kind, link and IPv4 connection state, raw address state/origins,
configured-default-route status, source availability, evidence references and
collection timestamps. Unknown enum values remain explicit and raw values are
retained. Active physical APIPA is ordered first; disconnected contexts last.
Virtual classification uses HardwareInterface, never name substrings. Virtual
APIPA is not automatically harmless. Disconnected retained configuration does not
establish a current internet-path fault. Automatic origin plus enabled DHCP makes
a missing usable lease only a possibility. A configured route is not proof of
connectivity. Source timestamps remain absent if the original check lacks them.

Focused regression command:

```powershell
powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1
```
