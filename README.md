# Windows network diagnostics

The 0.5.0 additions are documented stage by stage in
[Evidence extensions](docs/EVIDENCE-EXTENSIONS.md): incident/configuration inventory,
separate bounded observation, explicit interface probes, and offline DHCP/ARP
analysis. Native capture currently returns an explicit capability refusal;
it does not start a session. Ordinary snapshots remain passive by default.

Collector `0.6.0` (schema 10) collects bounded Windows 10/11 network snapshots for
intermittent DHCP, duplicate-IP, DNS, gateway, Ethernet, and Wi-Fi investigations.
It uses Windows PowerShell 5.1, built-in Windows commands, and .NET only.

## Quick start and capabilities

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -OutputRoot '.\output\reports [local]'
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 30 -OutputRoot '.\output\reports [local]'
```

| Mode | Evidence / limits |
| --- | --- |
| Snapshot | Passive checks by default; connectivity requires explicit opt-in |
| Observation | Bounded passive samples, stable-identity comparisons and structured Windows events |
| Offline verification | `Verify-NetworkDiagnostics.ps1 -Path <evidence.json>`; structure, references and hashes, not authenticity |
| Native capture/import | Existing safety refusal and VLAN/import behavior preserved; no new external-capture parser |

Read the [current reference](docs/CURRENT.md) for parameters, output placement,
exit status, schema/contract compatibility, synthetic examples and troubleshooting.
See the [current validation matrix](docs/VALIDATION-CURRENT.md) for tested coverage
and restrictions. Version-specific descriptions below retain historical context.
Raw checks are saved before analysis; final HTML identifies its evidence revision.
Collection, analysis and publication outcomes are separate. Final JSON or HTML
failure exits nonzero and leaves earlier artifacts recoverable when available.

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

Finalization includes a logical model derived only from completed successful
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
runs at finalization in 0.6.0; raw checkpoints remain frequent and derived status is pending until analysis.

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
| `PreviousSnapshotPath` | omitted | Optional schema 6/7/8/9 evidence JSON; same computer; bounded input worker |
| `IncidentContextPath` | omitted | Optional validated JSON user report, maximum 32 KiB; failure does not discard snapshot |
| `ProbeInterfaceIndex` / `ProbeSourceAddress` | omitted | Explicit single interface and local IP; both require connectivity opt-in |
| `MaxInterfaceProbes` | 16 | 1-64 checks including resolver preparation; applies only to explicitly selected interface |
| `ExpectationsPath` | omitted | Optional version 1 expectations JSON; bounded input worker |
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

Schema **9** retains the schema 2 identity/state fields: `ComputerName`, GUID `RunId`, `CollectorVersion`, `IsElevated`,
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
powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1
powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
powershell.exe -NoProfile -File .\tests\Test-DhcpReview.ps1
powershell.exe -NoProfile -File .\tests\Test-EventCorrelation.ps1
powershell.exe -NoProfile -File .\tests\Test-SnapshotComparison.ps1
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

Continuous monitoring, subnet scanning, Nmap, vendor lookup and Eero/UniFi
integrations remain out of scope. Separate bounded observation and optional capture
were authorized for 0.5.0; native capture currently refuses to start for the specific
ownership/filter limitations documented below. See [LICENSE](LICENSE).

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

## DHCP context, comparison and expectations (0.4.0 / schema 7)

**Competing DHCP servers: not assessed.** A healthy client using one selected
server can coexist with another server configuring other clients differently.
Neither a selected server nor successful DNS/TCP/HTTPS probes establishes that
only one DHCP server exists. No DHCP discovery traffic is sent.

The new per-interface DHCP section retains identity, current MAC, physical/virtual
classification, link/connection state, IPv4 prefixes, DHCP enabled state, selected
server, configured gateways/DNS/domain, lease times, and evidence references.
Missing fields stay unknown. Disconnected configuration is labelled retained.
Sentinels such as `255.255.255.255` remain raw evidence but are not usable selected
servers. Gateway/DNS values are configured values; their DHCP origin is not inferred.
WMI configuration supplies gateways/DNS first; default-route next hops and DNS
inventory provide fallbacks. The source and family-specific DNS inventory remain
visible. DNS fallback groups by address family, preserving preference within each
family; it does not establish a system-wide preference between IPv4 and IPv6.

Lease duration is expiry minus obtained time when both are valid and ordered.
Remaining seconds use the DHCP source check's completion timestamp (and can be
negative), not the viewer's clock. Offset ISO timestamps, PowerShell serialized
dates such as `/Date(0+0100)/`, and CIM DMTF timestamps are handled.
Invalid, absent and offset-free serialized times are unknown. Raw dates remain in
checks. Retained lease times on disabled/disconnected adapters do not establish
an active lease or current connectivity.

Optional inputs do not enable active probes:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -PreviousSnapshotPath '.\output\prior snapshot\evidence.json'
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -ExpectationsPath '.\output\expectations.json'
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -PreviousSnapshotPath '.\output\prior snapshot\evidence.json' -ExpectationsPath '.\output\expectations.json'
```

Paths are resolved from the caller's working directory. Each input is read once
by an isolated worker using `CheckTimeoutSeconds`, with the same hard termination
and cleanup as collection checks. Invalid JSON, unsupported baseline schemas,
incompatible computer names, invalid rules, permission failures and worker
timeouts are reported in `ContextInputs` and the derived section; ordinary
collection continues. Baselines newer than the current start are rejected by the
comparison. The input worker deadline bounds processing; there is no report-size
cutoff. Very large files can still exceed available memory or the worker deadline,
which is reported without losing ordinary collection. Input paths, effective rules and referenced
baseline identity are diagnostic data; keep them under ignored `output/`.

Adapters match only by normalized nonempty InterfaceGuid/SettingID GUIDs. These
are joined within a snapshot by interface index; disagreement or duplicate GUIDs
is ambiguous. There is deliberately no alias/MAC/index cross-snapshot fallback.
MAC changes remain visible. Computer name compatibility is a safeguard, not
cryptographic proof of machine identity. Adapter disappearance/appearance requires
complete, successful actual adapter inventories with unique, correlated identities;
unrelated IP-only records outside those inventories do not block absence assessment. Missing
values/checks are `Not assessed`, not configuration changes. Address and gateway
sets ignore order; DNS list order is significant. Advanced obtained/expiry times
are labelled `Lease refreshed`, without claiming a captured renewal exchange or
its cause. Baseline/current identity, collection state and timestamps are retained.
Two snapshots do not establish continuous configuration or health between them.

Create an expectations file with your own addresses. This example uses synthetic
identifiers and documentation-reserved addresses, not recommended network settings:

```json
{
  "Version": 1,
  "Defaults": {
    "AllowedDhcpServers": ["192.0.2.1"],
    "AllowedGateways": ["192.0.2.1"]
  },
  "Interfaces": [
    {
      "InterfaceGuid": "11111111-1111-1111-1111-111111111111",
      "Rules": {
        "AllowedDhcpServers": ["198.51.100.1"],
        "AllowedGateways": ["198.51.100.1"],
        "DnsServers": ["198.51.100.53", "203.0.113.53"]
      }
    }
  ]
}
```

`Defaults` and `Interfaces` are optional. Each override replaces only its supplied
fields; omitted fields inherit defaults. GUID overrides must be unique. Unknown
keys, invalid addresses, scalar address lists and empty lists are rejected. Server
and gateway rules mean every observed value must be in the allowed list, not that
every allowed address must be configured. `DnsServers` is **opt-in exact ordered
list equality**, using normalized IP spelling. Omit it to leave DNS unassessed.
There are no built-in expected addresses. Outcomes are `Match`, `Mismatch`,
`Not applicable` (DHCP disabled) and `Not assessed` (no rule, missing, ambiguous,
invalid or disconnected evidence). Assessment requires an up link; DHCP server
assessment also requires known enabled DHCP. A mismatch means only **outside
supplied expectations**, never a rogue server or proven root cause. Effective rules,
raw observations and source references accompany each assessment.

Historical event context uses named XML GUID/MAC fields, retaining each identifier
and its exact-match basis, current candidates and ambiguity. Index/name/LUID fields
are retained but not used alone for attribution. Unrecognized/localized fields
remain raw; messages are not parsed to guess an adapter. Exact GUID/MAC matches
are associations, not causal proof; a baseline match is labelled historical with
baseline run provenance and does not prove ownership at the event time. A MAC with
no current match includes current inventory coverage so missing inventory is not
mistaken for proof of absence. Contradictory identifiers are left separate.
Event time, signed age relative to snapshot start, source interval and event-limit
indicator are retained. There is no universal stale-event threshold. Unavailable
logs, raw messages/XML and provider availability remain in the original checks;
logs are never enabled. XML external entities/DTDs are prohibited.

Schema **7** introduced `DhcpSummary`, `SnapshotComparison`, `ExpectationAssessment`,
`HistoricalEventContext`, and `ContextInputs`, plus request flags in `Parameters`.
`ContextEvidence.ContractVersion=2` identified the schema-7 derived contract;
0.4.1 uses schema 8 / contract 3 as described below. Existing checks, collection/probe status semantics, findings and logical map remain
intact. Optional inputs retain their own collection status; they do not count as
network operation outcomes. In 0.6.0, derived sections are generated at finalization;
early raw checkpoints mark analysis pending. Source
references now resolve within this report, with explicit snapshot scope. No existing
reports are modified. Schema-6 and earlier schema-7 baselines are normalized from
raw `Checks`, so earlier derived serialization artifacts do not create changes.

### Scoped evidence and readable comparisons

Current source records stay in `/Checks` and are not copied into derived summaries.
The selected baseline's six relevant check families (adapters, DHCP configuration,
IP addresses, DNS servers, interface metrics, routes) are retained once under
`/ContextEvidence/Baseline/Checks`, with run identity and normalized interface summaries.
This bounds retained content by the consumed source families, not an arbitrary byte
cap. Prior baseline comparisons, context stores and nested history are never imported.
`ContextInputs` points to the retained baseline instead of embedding another copy.

Interface source descriptors retain status, collection times, `Scope`, `RunId` and
`EvidenceReferences`. Current source paths begin `/Checks/`; baseline source paths
begin `/ContextEvidence/Baseline/Checks/`. Comparison `BeforeReference` and
`AfterReference`, and historical event match references, contain `Scope`, `RunId`
and `Path` pointing to reusable interface summaries in the appropriate context.
Those summaries link to the actual retained records. Baseline paths must never be
interpreted against current `/Checks`. HTML renders baseline records once and links
to them; current links target the existing raw-check section.

Compared with the earlier uncommitted schema-7 draft, embedded `BeforeSources`,
`AfterSources`, per-summary source `Records`, and per-match source copies are removed
in favor of these references. DNS/route source details remain in their raw checks,
rather than duplicate inventory fields. Consumers of the draft should use the new
references and `ContextEvidence.ContractVersion`. Schema 6 raw checks and existing
findings remain unchanged. Missing derived lease scalars are JSON `null`; valid dates
are offset strings. Empty address arrays are `[]`, with null elements removed.
Availability continues to distinguish missing/unavailable/invalid/not-applicable data.

HTML comparison starts with snapshot identities/times and outcome counts, followed
by changed and lease-refreshed entries. Unchanged and not-assessed rows remain in
JSON and separate collapsed HTML sections. Adapter aliases and indices are visible;
the stable GUID remains in details. `BeforeContext`, `AfterContext` and `StateNote`
retain link/connection state. Configuration changes with the same disconnected
state on both sides explicitly say "Retained configuration changed on a disconnected
adapter." State transitions and unknown state are shown instead of an active-fault
claim. A zero assessed-change count does not erase coverage limitations.

Historical summaries show time, event ID/provider, an escaped message excerpt,
readable age and correlation result before expanded details. Message excerpts are
presentation only; structured XML still controls matching. Exact `AgeSeconds`,
identifiers, raw-message/XML references and limitations remain in JSON. Missing
times/descriptions and future-dated events are explicit. Unavailable/incomplete
inventory yields not assessed rather than confirmed absence; `NoCurrentMacMatch`
is null when absence cannot be assessed. Historical matches remain scoped to the
baseline run and do not establish adapter identity at the event timestamp.

MAC-event absence assessment uses the successful **adapter inventory**, not every
interface discovered in IP/DHCP/route evidence. A success with no adapter records
is insufficient. Each inventoried MAC must be a usable 48-bit unicast identity
represented in the correlated interface evidence. An empty/zero MAC is excluded
only when structured `InterfaceType` identifies loopback (24), tunnel (131) or PPP
(23), and `HardwareInterface` explicitly says false. These are built-in .NET
NetworkInterfaceType values. Virtual status, disconnection, names and missing MACs
alone do not establish non-applicability. Missing/malformed MACs on physical,
Ethernet-like or unknown types still prevent an absence conclusion. IP-only
interfaces without an adapter inventory record do not veto the assessment.

Sufficient evidence with no match yields `No current identifier match` and, for
MAC events, `NoCurrentMacMatch=true`. Insufficient evidence yields `Not assessed`,
`NoCurrentMacMatch=null`, a structured `ReasonCode` and readable `Reason`; HTML
shows the reason before raw details via `AssessmentReasons`. Missing, unsuccessful,
empty and insufficient-identity inventories have distinct reason codes. Exact
current matches remain explicit even if other identities are missing; multiple
current matches remain ambiguous. Historical matches remain separately scoped to
the baseline even when current absence is unassessable. Those event-correlation fields were additive to contract 2 and remain in contract 3. None attributes a current fault or an unmatched
old MAC to a particular adapter without historical evidence.

## Presence and observed-empty comparisons (0.4.1 / schema 8)

`ContextEvidence.ContractVersion=3` adds an explicit `ObservedEmpty` availability
value for IPv4, gateways and DNS collections. This distinguishes successfully
observed `[]` from `Missing`, `No matching record`, `Unavailable`, `NotCollected`,
`Incomplete`, `Invalid` and `Ambiguous` evidence. The comparison accepts
`Available` and `ObservedEmpty` on both sides: populated-to-empty and reverse
transitions are `Changed`; empty-to-empty is `Unchanged`. JSON still contains `[]`,
never a null element substituted for an empty collection. Expectations continue
to assess only nonempty `Available` configuration, so this change does not turn
missing or empty configuration into a confirmed policy mismatch.

Observed emptiness requires a complete snapshot and an unambiguously identified
inventoried adapter, plus the following source semantics:

- **IPv4:** one successful, well-formed `IPAddresses` enumeration contains no IPv4
  address for that adapter. This command enumerates address rows: no matching rows
  can establish emptiness when the adapter is independently known to exist.
- **Gateways:** one matching successful DHCP/configuration record has an existing
  gateway property containing null or an explicit empty array, and a successful,
  well-formed routes enumeration has no non-on-link default gateway for that
  interface. Null primary configuration alone is not proof. A missing primary
  record/property or unavailable route coverage remains unassessed.
- **DNS:** one matching successful configuration record has an existing DNS
  property containing null or an explicit empty array, and successful DNS inventory
  returns matching interface/family records with explicit empty `ServerAddresses`
  arrays. A missing DNS record, null provider array, duplicate family, or malformed
  enumeration remains unassessed. Complete enumeration covers the returned family
  records; no cross-family query-path preference is inferred.

Configured fallback route/DNS values take precedence over an empty primary field
when deriving the effective list; their source references remain visible. Failed
or ambiguous coverage is never converted into empty evidence. Duplicate checks,
malformed values and contradictory identity records remain explicit. Existing
disconnected-adapter state notes apply to removals and additions too; configured
changes are not active-path fault diagnoses.

Presence assessment uses actual `Adapters` records in both complete snapshots.
Each record must correlate within its snapshot to one unique stable identity;
missing/conflicting identities and duplicate GUIDs preserve uncertainty. IP-only
loopback or other non-inventory interface records cannot conceal an inventoried
adapter and do not veto absence. No cross-snapshot MAC, alias or index matching
is introduced. Appearance/disappearance rows include readable `Detail`, structured
`BeforePresenceReason`/`AfterPresenceReason`, and scoped inventory references, even
when the absent side has no adapter record. Both context and raw inventory remain
inspectable from the HTML.

Source descriptors now include `CheckReferences` and `EnumerationValid`. Check-level
references preserve provenance for an empty enumeration with no data-row reference.
Raw checks remain unchanged. Schema-6/7/8 baselines are re-derived from raw checks
using the same rules, not their older availability labels. Schema 8 explicitly
versions this semantic change; collector 0.4.0 cannot read a schema-8 baseline.

### Windows 11 follow-up in 0.5.4

Atomic temporary names are shorter while preserving replacement and backups.
The two path-sensitive orchestration tests place synthetic artifacts in unique
`%TEMP%/output/tests/` directories, independently of checkout length. Production
output remains under the checkout's `output/`; use a shorter checkout if its
runtime rejects long paths. Detailed findings, unresolved provider behavior and
completed targeted Windows 11 validation are in [WINDOWS11-FINDINGS.md](docs/WINDOWS11-FINDINGS.md).
Schema 9 and existing scoped contracts are unchanged.

### Windows 11 evidence corrections in 0.5.3

Provider details now retain query scope, identity field shapes and match outcomes.
Snapshot statistics/power queries target escaped literal names; observation
statistics retain one bounded batch enumeration. Exact installation identities
can match renamed adapters, while ambiguous/conflicting identities stay unassessed.
Wi-Fi unavailability uses structured service/capability evidence and retains the
native response. Observation timing and counter intervals use a shared same-run
monotonic basis, with collection and finalization durations reported separately.
Batch execution status and usable statistics coverage are separate.

Supplied Windows 11 evidence exercised core collection and DHCP comparisons.
The targeted 0.5.4 Windows 11 follow-up is complete: inventory agreement and real
atomic-write portability tests passed in the tested VM. Statistics returned no
rows and scoped power Error 31 persists; neither the VM nor Windows 11 is an
established cause. See [findings and completed validation](docs/WINDOWS11-FINDINGS.md).
Root schema 9 and DHCP comparison contract 3 remain unchanged; new provider,
Wi-Fi and timing evidence has scoped contract version 1.

### Observation corrections in 0.5.2

ObservationComparisonVersion 3 compares DHCP records independently by stable
identity and reports source coverage separately. Unmatched or conflicting records,
including IP-disabled records, remain unassessed with artifact-qualified reasons;
they no longer invalidate unrelated adapters. A partial source is never wholly
Unchanged. Configuration changes take precedence over lease timestamp refreshes.

The scheduler retains attempted and useful partial samples but avoids creating a
final empty sample when less than the one-second minimum worker budget remains.
The summary shows complete/partial counts and actual intervals. Statistics use
one bounded inventory worker per observation sample, with individual adapter
coverage. This reduces worker startup overhead; it does not guarantee a cadence.
Snapshot collection is unchanged. See docs/EVIDENCE-EXTENSIONS.md for contracts.

Passive validation from the repository directory (no active probes or capture):

powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 120 -IntervalSeconds 10 -CheckTimeoutSeconds 10
