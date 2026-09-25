# Current contracts and historical changes

See [CURRENT.md](CURRENT.md) for collector 0.7.0 / schema 11 and [draft release notes](RELEASE-NOTES-070.md). The versioned sections below preserve historical behavior.

# Persistence portability in 0.5.4

Atomic temporary filenames use a full GUID basename beside the destination,
preserving exclusive creation, atomic replacement and recovery backups. Path
errors retain their native InnerException with a shorter-path explanation where
appropriate. Test working roots are independent of checkout length. No serialized
snapshot or comparison meaning changes: schema 9 and all existing scoped contracts
remain unchanged. See [the follow-up](WINDOWS11-FINDINGS.md).

# Windows 11 corrections in 0.5.3

See [Windows 11 findings and validation](WINDOWS11-FINDINGS.md). Root schema 9,
ContextEvidence contract 3, DHCP ObservationComparisonVersion 3, and the existing
VLAN contracts are unchanged. These additions introduce independently scoped
contracts rather than reinterpret DHCP or baseline comparison data:

- Adapter detail `ProviderDiagnostic.ContractVersion=1`: query scope/status,
  row count, raw identity field values/property names, match basis/outcome and
  whether the error came from the native provider. Absent, present-unmatched,
  ambiguous, conflicting and failed-query cases differ. Errors retain original
  message, ID, category, exception type, HResult and exposed NativeErrorCode.
- Wi-Fi data or `Error.Evidence.ContractVersion=1`: native exit/text, structured
  service and complete/failed adapter inventory provenance, availability reason.
- Observation manifest/sample `Timing.ContractVersion=1`: parent run monotonic
  scheduling/intervals, requested duration, measured collection/finalization,
  wall-clock collection difference and termination reason. Finalization measurement
  ends before final metadata writes; their cost cannot be included in the metadata
  being written. CompletedAt has the same boundary. Initial directory/identity
  setup precedes the measured collection phase.
- Counter rows `CounterTiming.ContractVersion=1`: query windows measured with
  system Stopwatch.GetTimestamp, using the explicitly serialized parent origin,
  frequency and run ID. This is one machine-wide counter, not subtraction of
  independently started worker Stopwatches. Delta `TimingContractVersion=1`
  requires matching run identity and nonoverlapping monotonic query windows.
  Rates approximate intervals between query starts; actual samples occur within
  those windows. Older wall-clock-only counters are unassessed, not silently
  assigned rates. Raw legacy evidence remains readable.
- Sample/reference `StatisticsCoverage.ContractVersion=1`: batch execution status,
  expected and usable adapter counts, coverage status and batch check reference.
  Usable means at least one of the eight compared counter fields is present;
  individual missing fields remain unavailable. No zero counters are synthesized.

The original 0.5.2 description below documents prior behavior; 0.5.3 replaces its
name-only matching, snapshot-wide provider enumeration and wall-clock rate basis.

# Observation corrections in 0.5.2

Root schema remains 9; snapshot ContextEvidence contract remains 3. Observation
comparison/state contract changes from 2 to 3. Prior raw samples may be rederived;
older derived DHCP state is not silently compared using the new semantics.
The VLAN contracts, uncommitted at that historical stage and subsequently committed, remained unchanged.

Both BeforeAdapterContext and AfterAdapterContext are arrays: absent contexts are
[], never [null]. Valid objects retain null-valued properties. This representation
correction requires no additional schema or contract increment.
DHCP state retains DHCPEnabled, DHCPServer, gateways, DNS servers, DNSDomain and
lease obtained/expires timestamps; missing properties differ from observed nulls.
Configuration changes take precedence over timestamp-only LeaseRefreshed outcomes.
Each DHCP comparison has Adapters, Coverage, ChangedFields and Reasons.
Per-adapter outcomes are Changed, LeaseRefreshed, Unchanged or Not assessed.
Coverage is Complete only when all records can be assessed. Aggregate Changed or
LeaseRefreshed describes known results, not complete coverage; mixed unchanged
and unassessed records aggregate to Not assessed with Partial coverage.
SettingID and adapter GUID must be consistent with unique within-sample inventory
attribution. Index helps detect conflicts within a sample, never establish
cross-sample continuity. Missing counterpart rows do not establish removal.
IPEnabled=false records remain in evidence and coverage. Reasons contain Code,
Artifact, Path and Explanation. Before/after raw record references and context
remain available; HTML exposes outcomes and reasons before the detailed JSON.

A run finishing its allotted duration can be Complete while individual samples
are Incomplete. One second remains the minimum scheduling budget. Preflight and
post-checkpoint guards prevent an unattempted empty sample. Attempted failures
and timeouts remain; useful partial samples are not rejected for lacking a full
sample budget. Finalized sample references retain SHA256 and actual intervals.
Unexpected interruption leaves an incomplete recovery checkpoint.

ObservationStatistics enumerates hidden provider objects once in one bounded
worker. Per-adapter results use literal names with returned GUID/index conflict
checks; duplicate mappings are errors, missing rows are Unavailable, never zero.
Derived AdapterStatistics checks reference the raw batch check. Batch failure or
worker timeout propagates coverage gaps to each inventoried adapter. Counters
retain individual timestamps and existing reset/discontinuity rules. No adapter
class is excluded. Snapshot calls still enumerate independently; only an optional
pre-enumerated inventory parameter is shared. Worker tree termination is unchanged.
Real-machine performance and provider behavior require user validation; a ten-second
cadence is not promised.

# Evidence extensions: 0.5.0 / schema 9

## Targeted corrections in 0.5.1

Root schema **9** and snapshot `ContextEvidence.ContractVersion=3` are unchanged.
The following scoped contracts explicitly version new derived semantics; existing
raw checks, baseline loading, time budgets and passive defaults are unchanged.

- Observation manifests and samples now carry `ObservationComparisonVersion=2`.
  DHCP state uses `ContractVersion=2`; older derived DHCP state is not directly
  compared (Not assessed). Re-derive it from raw checks to apply the new rules.
  The same source-level comparison rows remain, with added `ChangedFields`,
  `Reasons` and limitations, and existing before/after sample/run references.
- Offline analysis uses `CaptureCorrelationVersion=2`; decoder output carries
  `VlanMetadataVersion=1`. Each decoded Ethernet DHCP/ARP record adds `VlanTags`,
  an ordered array containing TPID, TCI, VlanId, PCP and DEI. Untagged frames have
  `[]`. Correlation adds a readable `VlanScope` to transaction/ARP observations.

DHCP comparisons retain the collector's DHCPServer, DNSDomain, DHCPLeaseObtained
and DHCPLeaseExpires alongside DHCPEnabled, DefaultIPGateway and DNSServerSearchOrder.
Configuration records join adapter inventory within each sample by interface index,
then compare across samples using unique normalized SettingID/InterfaceGuid, never
array position, alias or MAC. Conflicting/malformed/duplicate identities, missing
records/properties and failed inventories are Not assessed with reasons. Reported
null and explicit empty arrays remain distinct from missing properties; changes
to null describe collected values, not proof of configuration removal.

A configuration difference is `Changed`, even if lease dates also change. Only
lease timestamp differences produce `LeaseRefreshed`; equal assessed fields are
`Unchanged`. LeaseRefreshed does not establish a captured renewal, and a server
change does not imply competing DHCP servers, malicious behavior or a network
fault. JSON and expandable HTML retain changed-field before/after values, value
states, identities and raw record paths scoped by the enclosing sample references.

VLAN grouping uses capture section/interface plus ordered TPID/VLAN-ID pairs.
PCP/DEI remain raw observations but do not split a VLAN scope. Untagged is distinct
from a priority tag with VID 0; differently ordered double-tag stacks remain
separate. The supported TPIDs remain 0x8100 and 0x88A8, at most two tags. Truncated,
third-tag and recognized unsupported-TPID frames yield explicit partial/unsupported
evidence and a raw block reference; raw artifacts are retained. Older decoded
packets without tag metadata, or with invalid/inconsistent metadata, produce
Not assessed correlation coverage and are not merged as untagged. Re-decoding the
original pcapng supplies VLAN evidence; no new capture format or live capture
backend is introduced.

This milestone is divided into four reviewable source/test groups. Ordinary
snapshots stay passive. No network changes, renew/release, reset, reconnect,
event-log enablement, execution-policy changes or mandatory dependencies are added.
Native capture is **not operational** in this version; its entry point records an
explicit capability refusal. Offline decoding is implemented separately.

## 1. Incident and configuration evidence

`src/AdditionalEvidence.ps1`, `src/NativeInventory.cs` and snapshot orchestration
add separate bounded checks. Existing IP address origins, route protocols, DHCP,
DNS and interface inventories are reused instead of queried a second time.

Create an incident file under ignored `output/`, for example `output/incident.json`:

```json
{
  "IncidentTime": "2026-01-01T12:00:00+00:00",
  "Description": "Connection stopped briefly",
  "AffectedApplication": "Example application",
  "ConnectionInUse": "Ethernet, according to user",
  "OtherDevicesAffected": "unknown",
  "FollowedEvent": "wake"
}
```

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncidentContextPath .\output\incident.json
```

Time with explicit offset, description, and yes/no/unknown other-device status are
required. All allowed fields are strings, at most 2048 characters; input is at most
32 KiB. Extra fields are rejected. Never include passwords or secrets in free text.
This is labelled `UserReported`, `Verified=false`; malformed/missing input is a
failed optional check, not an aborted snapshot or a verified cause.

`ConfigurationOrigins` refers to original check/data paths. Address PrefixOrigin
can support DHCP/manual classification; route Protocol=Dhcp supports DHCP. NetMgmt
does not establish human/manual origin. DNS stays Unknown: Get-DnsClientServerAddress
and Win32_NetworkAdapterConfiguration do not expose authoritative effective
DHCP/manual DNS origin. Registry/static values can be overridden by policy or
VPN; this implementation does not guess from DHCPEnabled or API selection.

VPN checks allowlist only connected Windows VPN connection name, GUID, status,
tunnel type, split-tunnel setting and user/all-user scope. No profile/EAP/key/secret
export occurs. Existing PPP/tunnel adapter records refer to their existing routes
by interface index. These are candidates, not proof of VPN purpose; profile GUIDs
are not adapter GUIDs. Third-party VPN identification and definitive VPN-profile
to adapter mapping remain unavailable when the native inventory supplies no key.

Proxy inventory covers current-process-user and machine WinINet registry values,
plus the WinHTTP machine default via WinHttpGetDefaultProxyConfiguration. It reads
only named settings, not registry exports or environment variables. Values containing
`@`, `?` or `#` are fully suppressed to avoid credential/query/fragment ambiguity,
including token suffixes after semicolons or whitespace. No PAC retrieval,
authentication, or proxy use is performed. Missing
settings remain unknown; application/session/policy effective decisions are not
inferred. Current user may differ from the affected application's account.

Enabled hidden/visible adapter bindings expose ComponentID/display name as installed
component observations, not causal diagnoses. This is not a complete WFP rule or
filter-state dump. Access failures are separate checks. Non-elevated collection is
supported where providers permit it; denied scopes remain explicit.

## 2. Bounded observation

```powershell
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 60 -IntervalSeconds 10 -CheckTimeoutSeconds 10
```

`-IncidentContextPath` is also supported. Duration is 10-600 seconds (default 60),
interval 5-120 seconds (default 10), per-check timeout 1-60 seconds (default 10).
This separate entry point has no active-probe/capture option. All checks are
sequential bounded workers; remaining session time caps each worker deadline.
Slow samples never overlap or queue. Timing includes collection; final cleanup and
durable writes can extend wall-clock time beyond the collection deadline.

Samples reuse adapter/IP/DHCP/DNS/metric/route/neighbour collectors, NIC service
discovery, per-adapter statistics, and existing enabled event-log collectors.
Events use separate bounded provider/log queries and per-log completed-window
cursors; record ID, log and timestamp deduplicate overlap. Limits and failures
remain in each sample. Log rotation, delayed event delivery and events beyond the
per-query limit can leave gaps; no logs are enabled.

Each sample has actual start/end times and start-to-start interval. Changes are
source-specific: failed/uncollected evidence is Not assessed, not Unchanged.
Counter deltas use stable GUIDs and actual counter start timestamps where present,
otherwise actual sample intervals with an explicit label. Decreases, missing
identity and observed link-state changes are discontinuities; no negative rates
are produced. A reset followed by counters overtaking their earlier values may be
invisible between samples. Errors/discards do not prove a physical fault.

The parent alone writes `output/observation-<computer>-<run>/evidence.json` and
separate `sample-NNNN.json` checkpoints. Completed samples are not rewritten each
interval. The small manifest references each sample and its SHA-256, state and
change summary. Comparison references name the run, sample and source check.
HTML links to sample artifacts and exposes change/coverage summaries. A partial
sample or manifest remains Incomplete after a hard termination; graceful cleanup
attempts a final checkpoint. This reuses the existing atomic-write and worker-tree
termination mechanisms, including their filesystem/platform limitations.

## 3. Explicit interface probes

Replace the example interface index and documentation address with the intended
local interface/source, and choose destinations you intend to contact:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncludeConnectivityTests -ProbeInterfaceIndex 7 -ProbeSourceAddress '192.0.2.10' -TcpDestinations '1.1.1.1' -HttpsEndpoint 'https://example.com/' -MaxInterfaceProbes 16
```

Use a separate invocation with an IPv6 source for IPv6. Family mismatches are
Unsupported, not silently sent via a different source. Both selection parameters
are mandatory together and require explicit connectivity opt-in. The check budget
includes name resolution and unsupported/skipped checks, not just successful
connections; TCP/HTTPS resolution is scheduled before unsupported DNS/ping checks.
Budget exhaustion is explicit and does not multiply across inventoried interfaces.

TCP/HTTPS validates that the requested source maps uniquely to the requested
index, applies Windows IP_UNICAST_IF/IPV6_UNICAST_IF, and binds the local endpoint
before connecting. Failure to establish binding has no unbound fallback. Results
retain intended index, requested source, binding status, route prediction,
observed socket source and its interface matches separately. This establishes
socket/outgoing-IP selection, not physical traversal beyond tunnels/filters.
Receive-path symmetry is not guaranteed. Shared probe budgets, worker overhead,
normal TLS certificate validation and direct HEAD/no-redirect behavior remain.

The OS resolver may be used to prepare a destination hostname; that is labelled
unbound preparation. Literal TCP destinations avoid that step. Server-specific
Resolve-DnsName and Ping APIs used here cannot guarantee this requested binding:
when an interface is selected, these probe kinds return Unsupported without
sending the query/ping. Route predictions never become verified interface probes.

## 4. Capture capability refusal and offline analysis

The native tool checks performed during development were help/export inspection
only. Microsoft documents pktmon component selection, DHCP-capable UDP filters,
ARP EtherType filters, bounded circular files and pcapng export:
[start](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/pktmon-start),
[filters](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/pktmon-filter-add).
The inspected Windows 10 pktmon CLI has global filters and an unqualified `stop`.
A mutex/status precheck cannot exclude another administrator replacing the session.
Stopping it later could stop someone else's capture. No global start/stop/filter
commands are issued by this implementation.

Local `netsh trace start/stop help` exposes a session name, but
`netsh trace show CaptureFilterHelp` does not expose a general UDP-port filter.
Using fixed header offsets would silently miss IPv4 options or weaken scope; it
was not selected as a DHCP capture backend. Its older documented single-session
limitations also differ from newer local help:
[netsh trace](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-trace).
The newer [independent Packet Monitor session API](https://learn.microsoft.com/en-us/windows/win32/pktmon/packetmonitor/nf-packetmonitor-packetmonitorcreatelivesession)
has relevant ownership semantics, but the required exports were absent in the
inspected local DLL. No adapter/filter/streaming backend for that API is claimed.
Windows 11 capabilities have not been tested and are not assumed identical.

```powershell
powershell.exe -NoProfile -File .\Capture-NetworkDiagnostics.ps1 -AdapterGuid '11111111-1111-1111-1111-111111111111' -DurationSeconds 30 -MaxSizeMB 16 -IncludeArp
```

This currently **returns exit 2 and an Unavailable report, never a capture**.
Replace the invented GUID only if reviewing a real capability request. Bounds are
1-4 requested GUIDs, duration 5-300 seconds and size 1-64 MiB. Metadata records
requested versus empty effective selections, tool/version/help capabilities,
run/elevation/timestamps, limits and no-session cleanup status. Drop/truncation
counts remain null. Native capture ordinarily requires elevation; no auto-elevation
occurs. A non-elevated or restricted context cannot resolve the ownership issue.
Existing sessions are neither adopted nor stopped. Start/stop cleanup, actual size
enforcement, interruption of a live session and capture timeout remain **unmet and
unvalidated** because no safe native backend is enabled; refusal tests do not
substitute for those lifecycle tests.

Offline analysis accepts an explicitly provided exported artifact:

```powershell
powershell.exe -NoProfile -File .\Import-NetworkCapture.ps1 -Path '.\output\selected-export.pcapng' -MaxPackets 10000
```

It copies at most 64 MiB into a new ignored output directory before decoding,
records SHA-256/length and safe relative artifact paths, and never embeds binary
capture data in HTML/JSON. No decoder failure deletes the raw copy. The supported
format is pcapng 1.0 little-endian sections, Ethernet interface blocks and enhanced
packet blocks, with microsecond/nanosecond timestamps. One/two VLAN headers,
unfragmented IPv4 UDP DHCPv4, and Ethernet/IPv4 ARP are supported. Big-endian,
other link types, timestamp offsets, fragments, overloaded/repeated DHCP options
and malformed/truncated structures are explicitly unsupported/partial. Parsing
stops at the first unsafe structure; preceding decoded evidence remains. This is
not a general ETL decoder and does not assume native capture implies decoding.

DHCP records preserve transaction ID, hardware type/address, distinct client ID,
message type, client/offered/requested/relay addresses, source/server identifier,
gateway/DNS/domain and lease/T1/T2 options, UTC packet timestamps and block offsets.
Raw option bytes remain represented as hex for inspection. Grouping is scoped by
capture section/interface, then transaction and explicit client identities, never hostname; missing versus present client ID
remains conservatively separate. Multiple offer responders, REQUEST selection and
ACK/NAK conflicts are observations. No first-offer-wins or applied-option claim is
made. ARP records retain sender/target IP/MAC and operation; differing claims are
not automatically duplicate-IP faults and are not merged with local/gateway nodes.
Capture-vantage gaps and incomplete exchanges cannot establish server exclusivity.
Offline analysis has no contemporaneous neighbour evidence; observation mode
collects it separately. Applied-configuration correlation remains manual.

## Contract, privacy and validation

Schema 9 adds snapshot origin/VPN context, new check families and optional binding
metadata, plus separately discriminated Observation/CaptureRequest/OfflineCaptureAnalysis
modes. DHCP ContextEvidence contract stays **3**. Snapshot baselines 6/7/8/9 load
from raw evidence; the new non-snapshot modes cannot be used as baselines. Older
collectors cannot load schema 9. Existing raw checks and provenance are preserved;
secret-bearing new inventory is deliberately allowlisted/redacted before persistence.

All captures, incident files and generated reports are sensitive local artifacts
under ignored output paths. Do not add them to Git. Source/tests use invented
identifiers and documentation-reserved addresses. See [VALIDATION.md](VALIDATION.md)
for actual normal PowerShell runs, storage restrictions, manual commands and unmet
live/elevated/Windows 11 validation. No network fault resolution is claimed.
