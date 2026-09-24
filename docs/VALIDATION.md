# Observation serialization follow-up and user validation: 0.5.2

## User-run evidence (reported separately from agent tests)

The user supplied the following validation for collector 0.5.2, schema 9,
observation comparison contract 3. Passive observation requested 120 seconds,
a 10-second interval and a 10-second check timeout; the user reported exit code 0.
The supplied artifact-review results confirmed ten complete samples, no empty or
partial samples, and matching manifest hashes for all ten samples.
Each of the nine DHCP comparisons retained 23 Unchanged records and two Not assessed
records; active Ethernet remained independently assessable. Average actual sampling
interval was approximately 11.94 seconds. Statistics batch duration was approximately
0.99-1.20 seconds.

This validates persistence and performance for that particular live run. It does
not establish live DHCP-change detection, counter-reset handling or Windows 11
compatibility. These are user-supplied validation results, not a new agent-run
observation or artifact reinspection. No reports or personal identifiers are tracked.

## Agent-run follow-up

Normal Windows PowerShell 5.1.19041.7725 script execution; synthetic inputs only.
Every command below was run from the repository directory:
- powershell.exe -NoProfile -File .\tests\Test-ObservationSerialization.ps1
  Exit 0, 25 serialized-JSON assertions: before/after empty arrays, one/multiple
  objects, null-valued object properties, comparison outcomes and references.
- powershell.exe -NoProfile -File .\tests\Test-LiveObservation.ps1
  Exit 0, 29 assertions; synthetic providers, modeled writes/hashes and clock.
- powershell.exe -NoProfile -File .\tests\Test-ObservationDhcp.ps1
  Exit 0, 17 synthetic assertions.
- powershell.exe -NoProfile -File .\tests\Test-Observation.ps1
  Exit 0, 13 synthetic assertions.
- powershell.exe -NoProfile -File .\tests\Test-ObservationModel.ps1
  Exit 0, 7 assertions; modeled persistence and collectors.
- powershell.exe -NoProfile -File .\tests\Test-AdditionalOrchestrationModel.ps1
  Exit 0, 8 assertions; modeled persistence and collectors.
- powershell.exe -NoProfile -File .\tests\Test-EntryLoading.ps1
  Exit 0, 8 entry/help and dot-source assertions, different directory/path with spaces.
- powershell.exe -NoProfile -File .\tests\Test-ObservationRun.ps1
  Exit 1, the restricted-agent persistence error below; also warned:
  "Final observation checkpoint failed; earlier files remain recoverable."
- powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
  Exit 1, the same persistence error:

Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12 char:49
CategoryInfo: NotSpecified: (:) [], ParentContainsErrorRecordException
FullyQualifiedErrorId: UnauthorizedAccessException

Passing total: 107 assertions across seven suites. Agent atomic-persistence tests
remain blocked; their failures are not passes and do not invalidate the separately
attributed successful user run. No access-control bypass or weakened persistence.
No live probes, capture or network changes. git diff --check passed.

Both absent adapter-context collections now serialize as [], while valid objects
and their null-valued properties remain intact. This corrects empty-collection
representation; collector 0.5.2, schema 9 and comparison contract 3 are unchanged.

# Initial live-observation corrections: 0.5.2

Agent-run validation, 2026-09-24. Windows 10 build 19045, non-elevated;
normal Windows PowerShell tests report 5.1.19041.7725. CurrentUser RemoteSigned;
no policy changes or bypass. Host shell is PowerShell 7.6.5, but every test below
was launched through powershell.exe -NoProfile -File.

Commands and final results (each explicitly observed exit code):
- powershell.exe -NoProfile -File .\tests\Test-LiveObservation.ps1
  Exit 0: 29 assertions; synthetic providers, controlled clock and modeled writes/hashes.
- powershell.exe -NoProfile -File .\tests\Test-ObservationDhcp.ps1
  Exit 0: 17 assertions; synthetic DHCP evidence.
- powershell.exe -NoProfile -File .\tests\Test-Observation.ps1
  Exit 0: 13 assertions, including counter deltas/discontinuities.
- powershell.exe -NoProfile -File .\tests\Test-ObservationModel.ps1
  Exit 0: 7 assertions, mocked persistence/collectors, including interruption.
- powershell.exe -NoProfile -File .\tests\Test-AdditionalOrchestrationModel.ps1
  Exit 0: 8 assertions, mocked snapshot orchestration.
- powershell.exe -NoProfile -File .\tests\Test-EntryLoading.ps1
  Exit 0: 8 assertions, normal entry/help and dot-sourcing from another directory
  and a path with spaces. No collection, probes or capture.
- powershell.exe -NoProfile -File .\tests\Test-ObservationRun.ps1
  Exit 1: File.Replace at src/State.ps1:12, UnauthorizedAccessException,
  "Access to the path is denied." Final checkpoint warning also emitted.
- powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
  Exit 1: same File.Replace restriction.

Final successful total: 82 assertions. Real atomic replacement, crash recovery and
end-to-end observation remain unverified in this restricted context. Model tests
do not validate filesystem durability or real provider performance.
An earlier DHCP test failed because its assertion read Reasons as strings; it now
checks structured Explanation. The final normal script execution passed.
An environment-inspection command incorrectly expanded the child version expression;
subsequent test outputs establish the Windows PowerShell version. CIM OS inspection
was access denied; the OS build was read through System.Environment instead.

No live probes, capture, configuration changes or actual observation were run.
Windows 11 remains untested. Prior user-run results below concern earlier versions.
Run the commands above in a normal Windows terminal to validate real persistence.
Optional passive validation from the repository:
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 120 -IntervalSeconds 10 -CheckTimeoutSeconds 10

# Final pre-commit review (0.5.0)

The final review tightened proxy redaction to suppress entire values containing a
query or fragment (including semicolon/whitespace suffixes), and removed the null
filter element from capture requests with ARP disabled. Focused normal Windows
PowerShell 5.1.19041.7725 reruns:

- `powershell.exe -NoProfile -File .\tests\Test-AdditionalEvidence.ps1`: exit 0,
  **15 assertions passed** (two new redaction regressions).
- `powershell.exe -NoProfile -File .\tests\Test-CaptureEvidence.ps1`: exit 0,
  **24 assertions passed** (one new filter-metadata regression).

These 39 agent-run assertions are separate from the earlier user-run transcript
below; no unrelated suites were rerun. No live capture or probes were performed
for this review. Existing validation limitations remain. The reviewed source,
tests and documentation are prepared for a normal commit/push preserving history.

---

# Evidence extensions: user-run validation (0.5.0 / schema 9 / contract 3)

The user supplied terminal output reporting **98 assertions passed across ten
suites** on Windows PowerShell **5.1.19041.7725**. The transcript shows normal
`powershell.exe -NoProfile -File` commands for nine suites and the additional
evidence suite's PASS line. Numeric exit codes, elevation and OS build were not
included in this transcript and are not inferred.

| Suite | Reported assertions passed |
| --- | --- |
| Test-AdditionalEvidence.ps1 | 13 |
| Test-DhcpOrchestration.ps1 | 8 |
| Test-EntryLoading.ps1 | 8 |
| Test-CaptureImport.ps1 | 3 |
| Test-CaptureEvidence.ps1 | 23 |
| Test-InterfaceProbes.ps1 | 10 |
| Test-ObservationRun.ps1 | 5 |
| Test-ObservationModel.ps1 | 7 |
| Test-Observation.ps1 | 13 |
| Test-AdditionalOrchestrationModel.ps1 | 8 |

This supplies user-run passes for all three suites that previously stopped at
atomic replacement in the agent environment: DHCP orchestration, observation
orchestration and capture import. ObservationRun used mocked collectors with real
atomic writes; CaptureImport verified raw artifact retention on decode failure.
The separate model tests still mock persistence, and interface probes mock sockets.
These results do not establish live observation, real interface-bound connectivity,
live capture, elevated execution or Windows 11 validation. The agent's failures
remain recorded separately below. No local paths or diagnostic identifiers were
copied into this record. No tests were rerun solely to record the supplied results.

---

# Evidence extensions: agent validation (0.5.0 / schema 9 / contract 3)

2026-09-24, starting from pushed `7b9ce4a`. At implementation time, changes were uncommitted. The agent
environment is Windows 10 build 19045, non-elevated, Windows PowerShell
5.1.19041.7725. Effective policy is RemoteSigned (CurrentUser; other scopes
Undefined). No policy/security settings were changed. Windows 11 and elevated
execution remain untested. No live capture, external connectivity probe, DHCP
traffic generation or network configuration change was performed. The existing
ProbeReview regression suite did open loopback-only TCP sockets; new interface
probe tests mock all socket/query operations.

All commands below used normal `powershell.exe -NoProfile -File` execution from
the repository directory. Passing results total **354 assertions across 14 suites**;
mocked storage tests are explicitly separated from real atomic persistence.

| Script under `tests/` | Exit | Result |
| --- | --- | --- |
| Test-AdditionalEvidence.ps1 | 0 | 13: incident validation/escaping, proxy redaction/access denial, origin uncertainty, VPN allowlist and route references |
| Test-AdditionalOrchestrationModel.ps1 | 0 | 8: default-passive/optional failure/budget/worker-input behavior; mocked persistence and collectors |
| Test-Observation.ps1 | 0 | 13: state/failure distinctions, counters/rates/resets, scoped event deduplication |
| Test-ObservationModel.ps1 | 0 | 7: timeout continuation, interruption and incomplete manifests; mocked persistence and collectors |
| Test-InterfaceProbes.ps1 | 0 | 10: intended/observed attribution, IPv4/IPv6 socket options, mismatch/unsupported paths, cleanup; fully mocked sockets |
| Test-CaptureEvidence.ps1 | 0 | 23: synthetic pcapng DHCP/ARP, selection/conflicts/client separation, malformed input/limits, refusal cases, raw-copy retention and encoded HTML; import report persistence mocked |
| Test-EntryLoading.ps1 | 0 | 8: actual entry-point `-?` help plus dot-sourcing from another working directory and a copied path with spaces; no collection executed |
| Test-Snapshot.ps1 | 0 | 42 existing snapshot assertions |
| Test-Presentation.ps1 | 0 | 33 existing presentation assertions |
| Test-SnapshotComparison.ps1 | 0 | 54 existing comparison/baseline assertions |
| Test-DhcpContext.ps1 | 0 | 52 existing context assertions |
| Test-DhcpReview.ps1 | 0 | 41 existing review assertions |
| Test-EventCorrelation.ps1 | 0 | 27 existing event-correlation assertions |
| Test-ProbeReview.ps1 | 0 | 23 existing timeout/TLS/failure assertions; loopback-only sockets |
| Test-ObservationRun.ps1 | 1 | Stopped at atomic replacement access denial; full persistence/interruption suite not verified |
| Test-CaptureImport.ps1 | 1 | Stopped at atomic replacement access denial; complete import/report persistence not verified |
| Test-DhcpOrchestration.ps1 | 1 | Stopped at atomic replacement access denial; complete snapshot orchestration not verified |

The three failed real-persistence runs produced:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12
FullyQualifiedErrorId: UnauthorizedAccessException
```

Observation also warned that the final checkpoint could not be saved. Earlier
checkpoint/raw files were left under ignored output/tests/. No delete/move fallback,
policy bypass or elevated retry was used. Separate model suites exercise control
flow with explicitly mocked persistence; they do not resolve or validate this
restriction. Test-Milestone2 version assertions were updated but that suite was
not rerun. Two development harness expectations were corrected (PowerShell JSON
Unicode HTML escaping and module autoload replacing a mock); final counts above
are the successful runs, not those initial harness failures.

## Native capability inspection

Read-only commands: `pktmon help`, `pktmon start help`, `pktmon filter add help`,
`pktmon stop help`, `pktmon etl2pcap help`, `netsh trace start help`,
`netsh trace stop help`, `netsh trace show CaptureFilterHelp`, and
`powershell.exe -NoProfile -File .\tests\Inspect-CaptureCapability.ps1` (exit 0).
Local pktmon file version: 10.0.19041.3636. Component/port/EtherType filtering is
present; CLI owner-scoped stop is absent. The required independent-session API
exports were not available in the local pktmonapi DLL. Inspection did not call
capture initialization/start/stop/filter mutation. Official Microsoft references
and the precise capability limitations are in [EVIDENCE-EXTENSIONS.md](EVIDENCE-EXTENSIONS.md).

## Reproduction commands

From the repository directory in normal Windows PowerShell, run each command and
record `$LASTEXITCODE`. These use synthetic/mock inputs and do not start capture:

```powershell
powershell.exe -NoProfile -File .\tests\Test-AdditionalEvidence.ps1
powershell.exe -NoProfile -File .\tests\Test-AdditionalOrchestrationModel.ps1
powershell.exe -NoProfile -File .\tests\Test-Observation.ps1
powershell.exe -NoProfile -File .\tests\Test-ObservationModel.ps1
powershell.exe -NoProfile -File .\tests\Test-ObservationRun.ps1
powershell.exe -NoProfile -File .\tests\Test-InterfaceProbes.ps1
powershell.exe -NoProfile -File .\tests\Test-CaptureEvidence.ps1
powershell.exe -NoProfile -File .\tests\Test-CaptureImport.ps1
powershell.exe -NoProfile -File .\tests\Test-EntryLoading.ps1
powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
```

The subsequent user-run passes for these suites are recorded above. Older user-run
results below apply only to earlier versions. New snapshot inventory providers, live observation,
real interface-bound TCP/TLS and actual capture are not live-validated. Entry help
and dot-sourcing are not full entry-point collection validation. Capture remains a
deliberate Unavailable result: there is no enabled native lifecycle backend, so
ownership/start/stop, duration/size enforcement and interruption cleanup of a live
session remain unmet. Refusal mocks are not live capture validation. The offline
decoder is deliberately limited, and applied configuration/neighbor correlation
with imported captures remains manual. No current network-fault resolution is claimed.

---

# User-run validation: 0.4.1 / schema 8 / contract 3

The user supplied a normal `powershell.exe -NoProfile -File` terminal transcript
reporting **182 assertions passed** across five suites on Windows PowerShell
**5.1.19041.7725**:

| Suite | Reported result |
| --- | --- |
| Test-SnapshotComparison.ps1 | 54 passed, 0 failed |
| Test-DhcpContext.ps1 | 52 passed |
| Test-DhcpReview.ps1 | 41 passed |
| Test-EventCorrelation.ps1 | 27 passed |
| Test-DhcpOrchestration.ps1 | 8 passed |

The pasted review-suite command contains an extra separator before `.ps1`; its
following output reports the expected 41-assertion DHCP review pass. The table
identifies that reported suite without claiming the pasted command spelling was
independently reproduced. Numeric process exit codes were not included in this
transcript and are not inferred.

This confirms a user-run orchestration-suite pass, distinct from the earlier
agent sandbox atomic-replacement failure below. It does not establish a new live
collector comparison run, Windows 11 validation, or resolution of a network fault.
No personal paths or diagnostic identifiers are retained here. No tests were
rerun merely to record this transcript.

---

# Snapshot comparison follow-up (0.4.1 / schema 8 / contract 3)

2026-09-24: follow-up to `e13631d`. Only synthetic fixtures were used. Raw reports
were not changed; no probes, DHCP traffic, network configuration changes or
execution-policy changes were performed. The final review prepares these changes
for a normal commit and push preserving the existing history.

## Before implementation: regression demonstration

The new `Test-SnapshotComparison.ps1` was added and run against unchanged production
code using `powershell.exe -NoProfile -File .\tests\Test-SnapshotComparison.ps1`.
The valid pre-fix run exited **1: 21 passed, 15 failed** across 36 assertions.
Failures were appearance/removal with an opposite IP-only loopback, duplicate
inventory ambiguity, and removal/addition/empty-to-empty/disconnected context for
the three address-list fields. Other uncertainty/fallback/order/policy cases passed.
An initial harness helper named `Compare` collided with PowerShell's built-in alias
(3 passed/33 failed); that helper was renamed before the valid baseline run, with
production code still unchanged. Those harness failures are not product regressions.

The causes were (1) a blanket check for GUIDs on every derived interface, including
non-inventory IP-only records, and (2) empty lists labelled `Missing`, excluded from
comparison by its `Available`-only gate. Duplicate adapter rows could also be hidden
by a single configuration SettingID; identity correlation now preserves ambiguity.

## After implementation: actual file execution

Normal Windows PowerShell **5.1.19041.7725** file execution in the existing Windows
10 non-elevated agent environment, from the repository directory:

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-SnapshotComparison.ps1` | 0 | 54 assertions passed (original 36 plus 18 focused coverage/provenance cases) |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1` | 0 | 52 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpReview.ps1` | 0 | 41 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-EventCorrelation.ps1` | 0 | 27 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1` | 1 | Ran, then stopped on atomic replacement access denial; complete suite not verified |

**174 assertions passed** across four suites. The orchestration error is:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12
FullyQualifiedErrorId: UnauthorizedAccessException
```

This is a restricted-agent storage failure during normal script execution, not an
execution-policy bypass or an inline test substitute. The subsequent user-run
0.4.1 orchestration-suite pass is recorded above. A live 0.4.1 collector comparison
remains unverified here. Windows 11 remains untested.

The new cases verify actual-inventory presence, incomplete/unavailable inventories,
missing/conflicting/duplicate identities, unchanged adapters, all three empty-list
transitions, malformed/unavailable/uncollected/ambiguous source coverage, null versus
empty provider properties, route/DNS fallback values and provenance, unordered IPv4
sets, disconnected state, expectations neutrality, serialized `[]`, scoped check-level
references for absent rows, and schema-7 raw-baseline normalization. Existing test
changes are version expectations and providing actual inventory in a previously
hand-constructed empty baseline; no storage checks were weakened. Milestone2's
version assertions were updated but that separate suite was not rerun in this task.

## Contract and limitations

Collector **0.4.1**, root **schema 8**, context **contract 3** explicitly version the
new `ObservedEmpty` availability semantics, `CheckReferences`/`EnumerationValid`
source metadata and presence inventory references. Schemas 6/7/8 are accepted as
baselines and normalized from raw checks. Old collector 0.4.0 cannot load schema 8.

Presence needs complete successful actual inventories with uniquely correlated
stable identities; an unidentified relevant adapter can conceal a counterpart,
while unrelated IP-only records cannot. Empty configuration needs a known adapter,
a complete snapshot and successful well-formed source enumeration. Address-row
absence establishes IPv4 emptiness; gateways additionally need matching configuration
and route coverage; DNS needs matching configuration and explicit empty provider
lists. Null primary fields alone, absent DNS objects, missing matching primary
configuration, invalid/duplicate rows and unavailable fallbacks remain unassessed.
This is deliberately conservative. Existing raw values/statuses are retained, and
expectations continue to leave empty configuration unassessed. No live network-fault
resolution or continuous state between snapshots is inferred.

Run the same five commands above in a normal Windows PowerShell terminal from the
repository directory; record `$LASTEXITCODE` after each. Optional passive comparison:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -PreviousSnapshotPath '.\output\prior snapshot\evidence.json'
$LASTEXITCODE
```

Replace the baseline path with a same-host schema-6/7/8 report. Active probes stay
disabled. All new test output is under ignored `output/tests/`.

---

# Historical MAC correlation regression fix (2026-09-24)

Focused change to the uncommitted 0.4.0/schema 7 implementation. ContractVersion
remains 2; `ReasonCode`, `Reason` and event `AssessmentReasons` are additive.

The regression was the revised blanket veto on any derived interface lacking
`Values.MacAddress`. The derived set includes non-MAC and IP-only interfaces, so
a successful adapter inventory could still become globally unassessable. Earlier
logic had reported absence without that veto. The fix does not revert to treating
inventory success alone as complete identity evidence: it examines actual adapter
records, excludes only explicit nonphysical loopback/tunnel/PPP identities without
MACs, and keeps missing, invalid, unknown-applicability or uncorrelatable relevant
identity evidence unassessed. Names and localized messages are not classification
or matching inputs. Raw checks and snapshot comparison matching are unchanged.

Normal Windows PowerShell 5.1.19041.7725 file execution from the repository directory:

| Command | Exit | Actual result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-EventCorrelation.ps1` | 0 | 27 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1` | 0 | 52 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpReview.ps1` | 0 | 41 assertions passed |

**120 assertions passed**. `git diff --check` also passed. No execution-policy
changes or inline workarounds were used. No restricted-agent failure occurred in
these three suites. Full orchestration/live collection was not rerun for this
focused change; previous restricted-agent atomic-replacement failures and the
separate user-run normal-terminal successes remain documented below. No Windows
11 validation or resolution of a real network fault is claimed.

New synthetic cases cover sufficient unmatched MACs; explicit non-MAC virtual
interfaces; unrelated IP-only records; missing/failed/unavailable/timed-out/empty
inventory; genuinely missing, malformed or unknown-applicability identities;
physical/nonphysical type conflicts; unique and duplicate exact matches;
historical-only matches; retained historical matches with unavailable current
inventory; no recognized XML identity; and structured/HTML consistency. The
regression fixture has invented event IDs 1001/1003 evidence for an old MAC absent
from both the current inventory and a post-recovery baseline. Its result is:

```text
CurrentInventoryStatus: Success
CurrentMatches: []
CorrelationSummary: No current identifier match
Confidence: No current identifier match
ReasonCode: NoCurrentIdentifierMatch
NoCurrentMacMatch: true
HistoricalMatches: []
```

The event IDs reproduce the reported event kinds; all adapter identities, MACs,
messages and network addresses in fixtures are synthetic. Artifacts stay under
ignored `output/tests/`; no real report was opened or modified for this fix.
Actual hosts with incomplete relevant metadata will still correctly receive
`Not assessed` with the reason visible in HTML. Matching is limited to available
snapshot evidence; it does not prove ownership of a MAC at the historical event
time or infer a current fault. No network activity, commit or push was performed.

---

# Schema-7 presentation/provenance refinement (2026-09-24)

Collector remains **0.4.0 / schema 7**, uncommitted. The revised derived contract is
identified by `ContextEvidence.ContractVersion=2`; the README documents removed
embedded-source fields and scoped replacement references. Raw checks are unchanged.

## User-run results, preceding this refinement

The user confirmed successful normal Windows PowerShell execution of the DHCP
context and orchestration suites and a passive baseline-comparison run. These are
user-run successes for the preceding uncommitted implementation, separate from
agent sandbox results. The supplied review did not include exact assertion counts
or a host-version transcript; no additional counts or Windows 11 validation are
inferred. No real report contents or identifiers are recorded here.

## Agent-run results after refinement

Normal `powershell.exe -NoProfile -File` execution, Windows 10 build 19045,
PowerShell **5.1.19041.7725**, non-elevated; CurrentUser RemoteSigned, all other
policy scopes Undefined. No policy changes or bypasses. All commands below were
run from the repository directory, with synthetic artifacts under `output/tests/`.

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpReview.ps1` | 0 | 41 assertions |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1` | 0 | 52 assertions |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions |
| `powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1` | 0 | 26 assertions |
| `powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1` | 0 | 94 assertions |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1` | 1 | Existing atomic-replacement restriction persists in agent sandbox |

**255 assertions passed** across five suites. The orchestration failure remains
`Exception calling "Replace" with "3" argument(s): "Access to the path is denied."`
at `src/State.ps1:12`, `FullyQualifiedErrorId: UnauthorizedAccessException`.
It does not contradict the user's normal-terminal orchestration success. No
attempt was made to bypass atomic replacement or weaken that test. A complete
agent-run passive comparison remains unverified; no new live probes were run.
Windows 11 remains untested.

The new suite verifies JSON nulls and empty arrays after round trip, explicit date
offsets, invalid/not-applicable availability, schema-6 normalization, raw evidence
preservation, current/baseline reference resolution, shared references, nested
history exclusion, stable size on repeated derivation, HTML ordering/counts,
disconnected/transition/unknown-state context, aliases/GUIDs, event descriptions,
escaping, future/missing timestamps, equivalent instants expressed with different
offsets, and ambiguous/unavailable-inventory correlations.

The serialization cause was reproduced in a normal PowerShell 5.1 file harness:
an empty conditional subexpression assigned inside a PSCustomObject had reference
identity with `System.Management.Automation.Internal.AutomationNull.Value` and
serialized as `{"Date":{}}`. An explicitly initialized `$null` scalar serialized
as `{"Date":null}`. The fix changes object construction; no serialized JSON string
replacement is used. Address arrays filter null elements before serialization.

## Reproducible synthetic size measurement

`tests/fixtures/DhcpReview.ps1` defines twelve synthetic adapters, one configured
gateway change on a disconnected adapter, two advanced lease timestamps and twelve
structured events. Fixed synthetic run IDs, timestamps and source payloads make
the same fixture reusable. The pre-refinement source was copied, without edits,
to ignored `output/tests/review-before/src/` before implementation.

```powershell
powershell.exe -NoProfile -File .\tests\Measure-DhcpReport.ps1 -SourceRoot .\output\tests\review-before
powershell.exe -NoProfile -File .\tests\Measure-DhcpReport.ps1
```

Both measurement commands exited 0 and wrote fresh reports under `output/tests/`.
The first command uses the preserved local pre-refinement copy; on another checkout,
`-SourceRoot` must point to a saved copy of that implementation. The fixture and
measurement script are tracked source; the old implementation copy and reports are
local ignored artifacts.

| Artifact | Before (bytes) | After (bytes) | Reduction |
| --- | ---: | ---: | ---: |
| JSON | 4,972,870 | 1,212,261 | 75.6% |
| HTML | 3,949,567 | 338,573 | 91.4% |

The reduction comes from eliminating repeated source-record copies per comparison
row/correlation and rendering reusable raw evidence once, not truncating evidence
or imposing a report-size cap. The previous 8 MiB input cap is removed: input reads
remain inside the existing bounded worker; retained baseline content is limited to
the six consumed source-check families, with no recursive history. Large inputs
can still time out or exhaust worker resources and are reported as input failures.

Manual normal-terminal checks and a fresh passive comparison:

```powershell
powershell.exe -NoProfile -File .\tests\Test-DhcpReview.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -PreviousSnapshotPath '.\output\prior snapshot\evidence.json'
$LASTEXITCODE
```

Replace the baseline path with a same-host schema-6/7 evidence file. Add
`-ExpectationsPath '.\output\expectations.json'` only when supplying expectations.
These commands keep active probes disabled. No original real reports were edited,
and no commit or push was performed.

---

# DHCP context review (0.4.0 / schema 7, agent-run)

2026-09-24: normal `powershell.exe -NoProfile -File` execution on Windows 10
build 19045, Windows PowerShell **5.1.19041.7725**, non-elevated. The dedicated
Windows PowerShell host check reported CurrentUser **RemoteSigned**, with all
other execution-policy scopes Undefined. No policy changes or bypasses were used.
Windows 11 remains untested. No external probes, DHCP discovery, packet capture,
network changes, commits or pushes were performed.

Commands run from the repository directory:

| Command | Exit | Actual result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1` | 0 | 52 assertions passed on the final focused run |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1` | 0 | 26 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1` | 0 | 94 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1` | 1 | Atomic replacement denied; full orchestration remains unverified |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | 1 | Atomic replacement denied; full suite remains unverified |

The four passing suites total **214 assertions**. The new focused suite tests
schema-6 baseline loading in a real bounded worker, selected-server coverage
limits despite successful client probes, per-interface provenance, lease math
and serialized dates, stable-GUID MAC changes, lease refresh, DNS order, omitted
versus explicit expectations, per-field overrides, disconnected/missing/sentinel
values, conflicting/duplicate GUIDs, malformed/incompatible inputs, historical
old-MAC correlation, event XML restrictions, future-baseline rejection, optional
worker-timeout presentation, raw evidence preservation and HTML escaping.
The orchestration suite uses mocked collectors but real bounded optional-input
workers and real atomic checkpoints. It is intentionally not weakened to avoid
the storage restriction.

Both incomplete suites returned this error at `src/State.ps1:12`:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
CategoryInfo: NotSpecified: (:) [], ParentContainsErrorRecordException
FullyQualifiedErrorId: UnauthorizedAccessException
```

A fresh copy of the actual entry point and `src/` was placed under ignored
`output\tests\context validation\`. With working directory `output\`, normal
`powershell.exe -NoProfile -File` calls using absolute quoted paths ran:

- `Test-ContextHost.ps1`: exit 0, recorded the host details above and successfully
  dot-sourced the copied Core/State modules from the path containing spaces.
- `Collect-NetworkDiagnostics.ps1 -CheckTimeoutSeconds 5`: exit 1, the same
  atomic-replacement error in the copied State module. Script loading succeeded,
  but **full passive entry-point collection is unverified** in this sandbox.

This was real file execution, not inline execution standing in for end-to-end
validation. The focused report test successfully created a new synthetic report;
that does not prove replacement of existing checkpoints works in this context.
All new test/copy artifacts are under ignored `output/tests/`; no original reports
were changed. Input comparison is limited to GUID identities and schemas 6/7,
with an 8 MiB input cap. Event correlation recognizes explicit named XML fields;
unrecognized identifiers remain raw. No LAN-wide DHCP assessment or actual fault
resolution is claimed. Historical user results below apply to prior versions,
not this release.

Manual validation from the repository directory in a normal Windows PowerShell
terminal (record `$LASTEXITCODE` after each command):

```powershell
powershell.exe -NoProfile -File .\tests\Test-DhcpContext.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
$LASTEXITCODE
```

To validate optional inputs, replace the baseline path with a previous same-host
schema-6/7 snapshot and create the expectations file using the README format:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -PreviousSnapshotPath '.\output\prior snapshot\evidence.json' -ExpectationsPath '.\output\expectations.json'
$LASTEXITCODE
```

These commands leave active probes disabled. Review the new JSON/HTML sections;
do not add the resulting diagnostics or real identifiers to tracked documentation.

---

# Pre-commit documentation review

2026-09-23: clarified generated no-match records versus original provider errors.
The agent reran `powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1`
from the repository directory using normal script execution: **26 assertions
passed, exit 0**. This focused rerun is separate from the user-run results below;
unrelated suites were not rerun. Existing sandbox limitations remain applicable.

# User-run validation of 0.3.1 / schema 6

The user supplied a normal Windows PowerShell transcript: Test-AdapterApipa.ps1
passed **26 assertions**, exit **0**; the default passive collector returned
exit **0**. The agent independently read the saved evidence and verified collector
**0.3.1**, schema **6**, CollectionStatus **Complete**, PowerShell
**5.1.19041.7725**, **IsElevated=False**, and active connectivity tests disabled.

The 72 checks contain **31 Success, 40 Unavailable and one Skipped**, with no
Failed or TimedOut records. All **39 missing adapter-provider checks** now report
Unavailable, retain adapter identity, and carry the explanation "No matching
adapter-provider object was returned." All 39 agree with logical-map coverage.
For successful inventory enumeration with no literal match, the explanation and
AdapterProviderObjectMissing record are collector-generated; no native provider
exception exists. Thrown provider errors instead retain their original message,
ID, category and exception type alongside any explanation/classification.
The remaining unavailable check is the DHCP Operational log; connectivity is
skipped. This validates live targeting and classification on this host, not a
claim that missing objects establish faulty or unsupported hardware.

All **five APIPA addresses** remain represented with evidence references and
collection timestamps: one on an up virtual/software adapter and four on
disconnected adapters (one physical, three virtual/software). None is attributed
to an active physical interface. The up virtual finding precedes disconnected
findings. All four correlated source categories report successful matching
coverage for these findings. No real addresses, aliases, descriptions, machine
names, paths, MACs, SSIDs or run identifiers are included here.

The user transcript confirms report production and the saved evidence remains
ignored by Git. This is a user-run non-elevated passive validation, not a new
agent collection. It does not establish resolution of a network fault or Windows
11 compatibility through testing; Windows 11 remains untested. Other test suites were not included in this
transcript; their prior results and sandbox restrictions remain documented below.
No original diagnostic report was modified; no commit or push was performed.

---

# Adapter availability/APIPA fixes (0.3.1, schema 6)

2026-09-23: Windows 10, build 19045, Windows PowerShell 5.1.19041.7725,
non-elevated agent sandbox, effective policy RemoteSigned. No policy changes,
restriction bypasses, external probes, network changes, commits or pushes.

Targeting inspection: the adapter inventory already included hidden adapters.
The prior provider calls used escaped Name patterns and IncludeHidden. Local
NetAdapter CDXML confirms these providers expose Name queries and IncludeHidden.
To avoid assuming that pattern escaping is portable across the provider boundary,
new calls enumerate hidden provider objects and match names literally in PowerShell.
Available returned interface index/GUID must agree with the inventoried identity.
This is a targeting correction/guard, not proof that the earlier real failures
were caused by a targeting bug or by unsupported hardware. No real reports were
modified or reclassified.

Normal file commands and actual results from the repository directory:

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1` | 0 | 26 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1` | 0 | 94 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1` | 0 | 23 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Dns.ps1` | 0 | 39 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Presentation.ps1` | 0 | 33 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | 1 | File.Replace access denied; full suite remains unverified |
| `powershell.exe -NoProfile -File .\tests\Test-Probes.ps1` | 1 | TLS initialization failed with "No credentials are available in the security package"; full suite unverified |

The focused suite tests literal names containing spaces/brackets/*/?, hidden
inventory inclusion, matching identity, mismatched identity, structured missing
objects for both providers, permission/unexpected errors, and unrelated
ObjectNotFound errors. APIPA cases include active/disconnected physical, active
virtual and missing adapters; multiple addresses; healthy physical alongside
other APIPA interfaces; unknown enum retention; evidence references/times; HTML
encoding; and consistent unavailable/timeout statuses in summaries/map coverage.
The existing probe-review suite additionally exercises actual worker termination,
cleanup and continuation. All new output remains under ignored output/tests/.
No Windows 11 or resolution of a real network fault is claimed. These are
synthetic tests; actual provider matching after this change still needs validation.

The milestone suite error remains:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12 char:49
FullyQualifiedErrorId: UnauthorizedAccessException
```

Manual commands, from the repository directory in your normal terminal:

```powershell
powershell.exe -NoProfile -File .\tests\Test-AdapterApipa.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
$LASTEXITCODE
```

The collector command is passive. Review adapter Unavailable explanations and
original errors separately, and APIPA context in Observations/Hypotheses and
Findings.ApipaDetails. A successful collector exit does not establish connectivity.
Provider inventories and adapter identities can change between sequential checks;
missing returned identity fields limit verification. Enumeration is repeated per
bounded adapter check and may be slower than name-pattern queries. No existing
user diagnostic artifacts were changed.

---

# User-run logical-map validation: completed with partial provider coverage

The user supplied normal Windows PowerShell terminal output for:

```powershell
powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
$LASTEXITCODE
```

The logical-map suite passed **94 assertions**, exit **0**. The passive collector
also returned exit **0**. The agent independently inspected its saved JSON:
collector **0.3.0**, schema **5**, CollectionStatus **Complete**, Windows PowerShell
**5.1.19041.7725**, **IsElevated=False**, and active connectivity tests disabled.
HTML exists. Generated evidence remains ignored by Git. No real machine names,
paths, addresses, MACs, SSIDs or run identifiers are copied here.

The report contains **72 check records**: **31 Success, 39 Failed, one Unavailable,
one Skipped**. Adapter statistics succeeded for **10 of 26** adapters; power
management succeeded for **3 of 26**. The remaining adapter checks report
`CmdletizationQuery_NotFound_Name` for their respective provider cmdlets, with
category `ObjectNotFound`. This records missing provider objects for the requested
names, not proof of network faults or a confirmed explanation of why those objects
were absent. The DHCP Operational log remains unavailable and connectivity skipped.
Successful adapter results were retained despite other adapters failing.

The generated map reports **29 interface contexts, 27 interface-scoped subnets,
162 neighbour-cache observations and 3 eligible endpoint observations**. These are
logical evidence counts, not physical device counts. There are **42 coverage gaps**,
including failed/unavailable sources, skipped connectivity, unknown Layer 2 and
unavailable structured Wi-Fi associations. The extra interface contexts can come
from sources beyond adapter inventory; they are not claimed to be extra devices.

This validates normal non-elevated end-to-end passive collection, map/report
production and partial real adapter-provider availability on the user's host.
The 39 failed checks remain limitations; exit 0 means collection completed, not
that every provider succeeded. No Windows 11, physical topology/Wi-Fi path or real
fault validation is claimed. Other suites were not included in this transcript;
earlier agent sandbox restrictions below remain accurately recorded. No new
collection, policy change, configuration change, commit or push was performed to
inspect these results.

---

# Logical network milestone validation (0.3.0, schema 5)

## Latest user-reported validation of d4d5c4d

The user reports Windows 10 Pro build 19045, Windows PowerShell 5.1,
**non-elevated execution**, **198 assertions passed across six suites**, and
**passive collector exit 0**: 18 successful checks, one unavailable DHCP
Operational log, and one skipped connectivity group. These are the user's
results for commit d4d5c4d, not agent-run validation of the new map milestone.
No real identifiers or diagnostic paths are included. Windows 11 remains untested.

## Agent validation of the logical map changes

2026-09-23: Windows 10 Pro build 19045.7725, Windows PowerShell
5.1.19041.7725, non-elevated sandbox, effective policy RemoteSigned. Normal
script execution was used; no policy changes or restriction bypasses. All suites
were invoked from the repository directory:

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1` | 0 | 94 logical-map assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | 1 | Atomic File.Replace access denied; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-Probes.ps1` | 1 | TLS security-package initialization restriction; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1` | 0 | 23 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Dns.ps1` | 0 | 39 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Presentation.ps1` | 0 | 33 assertions passed |
| `powershell.exe -NoProfile -File .\output\Validate-ReviewSyntax.ps1` | 0 | 21 PowerShell files parsed with the 5.1 AST parser |

The local syntax harness is ignored generated output. The tests execute actual
.ps1 files and normally dot-source helpers; syntax parsing is not an end-to-end
collector validation. Unchanged blocking errors:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12 char:49
FullyQualifiedErrorId: UnauthorizedAccessException

Assertion failed: HTTPS TLS timeout retained (actual outcome: Failed; error:
Exception calling "BeginAuthenticateAsClient" with "3" argument(s):
"No credentials are available in the security package")
At tests/Test-Probes.ps1:8 char:28
```

Map tests cover two physical interfaces sharing a prefix, overlapping ranges,
multiple addresses/default routes, scoped IPv6 and IPv4 neighbours, stale,
incomplete/unreachable/permanent/unknown states, broadcast/multicast filtering,
missing MACs, repeated IP/MAC observations without merging, separate remote probe
endpoints, missing/failed coverage, deterministic generation and provenance on
every node/relationship. Hostile map fields are HTML-encoded, neighbour details
collapse, and original evidence remains unchanged. Adapter mocks exercise counters,
unsupported providers, permission failures and successful power evidence. Mocked
orchestration verifies an independent timeout budget for each adapter check and
continuation after failure. Its persistence writer is mocked, not a claim that
sandbox File.Replace worked. Synthetic reports use the real writer in new test
directories under ignored output/tests/; existing user reports were not touched.

## Manual passive validation

From the repository directory in a normal Windows PowerShell terminal:

```powershell
powershell.exe -NoProfile -File .\tests\Test-LogicalNetwork.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 30
$LASTEXITCODE
```

The passive command enables no active probes. Open its printed HTML summary and
review the logical overview, per-interface neighbours, coverage and per-adapter
check statuses. Check schema 5/collector 0.3.0 and Complete in JSON; a successful
collector exit is not proof that every provider succeeded. Provider-specific
permissions or unavailable power fields should remain explicit per adapter.
All other regression commands are listed in the table above.

## Remaining limitations

No Windows 11, physical Wi-Fi, actual topology, real fault, or new live adapter
statistics/power-provider validation was performed. The map uses the local host's
partial snapshot only. Broadcast detection depends on known local prefixes;
non-Ethernet MAC formats are conservatively excluded from endpoint-observation
counts. Provider calls and snapshots are sequential, not atomic. Cache entries,
route predictions and socket endpoints do not establish physical wiring or
present reachability. Structured Wi-Fi relationships remain unavailable.
The full persistence and TLS suites still need normal-terminal execution for
these edits; earlier successes do not establish a pass for this version.
No commit or push was performed for this milestone.

---

# User validation and console presentation update

The user reports **165 passing assertions across five suites** and an active
collector exit code of **0**. Reported outcomes: **six legacy DNS queries skipped,
six DNS queries succeeded, TCP succeeded, and both HTTPS probes succeeded**.
These are user-reported results for the DNS-selection update, not agent reruns.
No machine names, interface aliases, server addresses, run IDs or diagnostic paths
from that run are included here. The user did not separately report test-process
privileges or environment details for this validation; none are inferred.

Focused presentation validation uses normal Windows PowerShell 5.1 file execution
in the previously documented non-elevated Windows 10 sandbox:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Presentation.ps1
powershell.exe -NoProfile -File .\tests\Test-Dns.ps1
```

Presentation suite: **33 assertions passed, exit 0**. DNS suite: **39 assertions
passed, exit 0**. Presentation tests cover widths 20, 40, 60, 80 and 120, complete
wrapped result values/reasons, associations once per target, readable numeric
enums, explicit unknown/missing values, unchanged raw JSON and failure reasons.
These tests are synthetic and do not send external probes. Historical sandbox
failures below remain recorded, distinct from the user's successful validation.

---

# DNS selection/error validation (0.2.2, schema 4)

2026-09-23, agent sandbox: Windows 10 Pro 22H2 build 19045.7725,
Windows PowerShell 5.1.19041.7725, non-elevated. Effective/CurrentUser execution
policy RemoteSigned; all other scopes Undefined. No policy change, restriction
bypass, external active probe, dependency installation or network-setting change.
No commits or pushes; existing privacy-corrected history preserved.

## Normal file execution results

All suites were invoked from the repository directory with the exact commands:

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | 1 | Checkpoint File.Replace access denied; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-Probes.ps1` | 1 | TLS initialization security-package restriction; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1` | 0 | 23 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Dns.ps1` | 0 | 39 assertions passed |
| `powershell.exe -NoProfile -File .\output\Validate-ReviewSyntax.ps1` | 0 | 18 PowerShell files parsed with the 5.1 parser |
| `powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncludeLegacyDnsTargets` | 1, expected | Rejected with `IncludeLegacyDnsTargets requires IncludeConnectivityTests.` before collection |

The syntax harness is ignored local output, not a replacement for actual script
execution. The test scripts normally dot-source the source files; workers in the
review suite run as actual Windows PowerShell processes. Existing sandbox errors
remain unchanged:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12 char:49
FullyQualifiedErrorId: UnauthorizedAccessException

Assertion failed: HTTPS TLS timeout retained (actual outcome: Failed; error:
Exception calling "BeginAuthenticateAsClient" with "3" argument(s):
"No credentials are available in the security package")
At tests/Test-Probes.ps1:8 char:28
```

## New coverage and isolation

DNS tests cover all three exact legacy addresses; compressed, expanded and scoped
forms; parsed equality and scope-aware deduplication; retention of original
spellings, zones and multiple configured associations; unrelated fec0 targets;
VPN/virtual/disconnected/no-default-route eligibility; family-specific interface
state; uncertain unzoned IPv6 targets; default skipping; explicit opt-in; and
rejecting legacy opt-in without active-probe permission.

Structured synthetic exceptions cover native timeout, NXDOMAIN, refused,
server-failure and unknown codes, localized messages, inner exceptions and
Win32-facility HRESULT decoding. Empty answer sets and message/ID text do not
invent NXDOMAIN. Tests distinguish DNS timeout from worker timeout, verify skipped
result counts/HTML escaping, and ensure no DNS root-cause hypothesis is generated.
The DNS orchestration executor and report checkpoint writer are mocked; this
verifies scheduling and skip behavior, not successful real atomic checkpoints.
The final synthetic HTML uses the real report writer in a new directory.

All new synthetic reports, orchestration snapshots and intentionally corrupt
recovery fixtures are under ignored `output/tests/`. Existing user reports and
older test artifacts were neither altered nor deleted. Raw live DNS inventory
was not needed or copied into tests or documentation.

## Manual commands and limitations

From the repository directory in your normal Windows PowerShell terminal:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Dns.ps1
$LASTEXITCODE
```

For an optional active validation with default legacy skipping:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncludeConnectivityTests -TcpDestinations 1.1.1.1 -DnsQueryName example.com -HttpsEndpoint https://example.com/
$LASTEXITCODE
```

Only if you intend to query legacy addresses as well, add
`-IncludeLegacyDnsTargets` to that active command. Neither command was run by the
agent. Review the DNS table's collection status, probe outcome, classification,
reason and configured associations separately; configuration is not an observed
source path. Keep raw diagnostic files private.

No live DNS-error-code validation or Windows 11 validation for this update.
Historical user-run success below applies to 0.2.1, not a new 0.2.2 end-to-end run.
Full persistence/TLS suites still need normal-terminal execution. Synchronous
Windows providers can outlast the cooperative probe budget and remain bounded by
the hard worker deadline. Missing or conflicting numeric codes remain Unknown.
Numeric scope IDs are preserved, not verified as actual routing zones; ambiguous
scope associations cannot prove the query path.

---

# Probe review validation (0.2.1, schema 3)

Date: 2026-09-23. Windows 10 Pro 22H2, build 19045.7725;
Windows PowerShell 5.1.19041.7725; non-elevated agent sandbox. Effective and
CurrentUser policy: RemoteSigned; MachinePolicy, UserPolicy, Process and
LocalMachine: Undefined. No policy changes, bypass flags, dependencies, network
configuration changes, or external active probes were used. The existing cleaned
Git history remains unchanged; nothing was committed or pushed.

## Latest user-run opt-in validation: passed

The user supplied a normal-terminal collector transcript on 2026-09-23 with
`$LASTEXITCODE` **0**. The agent independently read the saved JSON: schema 3,
collector 0.2.1, PowerShell 5.1.19041.7725, CollectionStatus Complete, populated
start/end timestamps, **IsElevated=True**, and 37 completed check records.
Connectivity was enabled; gateway ping was disabled. Recorded budgets were
10 seconds per probe, 15 seconds additional worker overhead, and 30 seconds per
passive check. This was user-run validation, not an agent-run external probe.

Collection statuses: **36 Success, one Unavailable**. Network outcomes were
separate: six server-specific DNS queries failed, six DNS queries succeeded,
TCP succeeded, both IPv4 HTTPS probes succeeded, and gateway neighbour evidence
was Observed without ICMP. The TCP/HTTPS records retain observed socket endpoints;
both HTTPS records retain all four completed stages. No worker or probe timeout
was reported. Failed DNS queries do not establish a DNS root cause or contradict
successful queries against other configured servers.

The HTML exists and both generated report files are ignored by Git. No diagnostic
identifiers or raw report contents were copied into tracked documentation. This
run validates actual opt-in collection and report persistence in the user's
elevated Windows 10 terminal. It does not validate Windows 11, IPv6 connectivity
success, real failure/timeout paths, or establish that an intermittent fault is
resolved. The test suites were not included in this transcript; their sandbox
results below remain unchanged.

## Agent sandbox results

All commands below used normal `.ps1` file execution from the repository directory:

| Command | Exit | Result |
| --- | --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | 0 | 42 assertions passed |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | 1 | Atomic checkpoint `File.Replace` denied; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-Probes.ps1` | 1 | Real TLS initialization failed before expected timeout; full suite unverified |
| `powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1` | 0 | 23 assertions passed |
| `powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 20` | 1 | Atomic checkpoint replacement denied; not an end-to-end pass |
| `powershell.exe -NoProfile -File .\output\Validate-ReviewSyntax.ps1` | 0 | All 16 source/test/fixture/entry-point PowerShell files parsed with the 5.1 AST parser |

The syntax harness is a generated local artifact under ignored output/. It is not
an inline replacement for entry-point execution. Tests dot-source the actual source
files normally; real workers execute via `powershell.exe -NoProfile -NonInteractive
-File`. No out-of-sandbox rerun was used for these results.

The checkpoint error remains:

```text
Exception calling "Replace" with "3" argument(s): "Access to the path is denied."
At src/State.ps1:12 char:49
CategoryInfo: NotSpecified: (:) [], ParentContainsErrorRecordException
FullyQualifiedErrorId: UnauthorizedAccessException
```

The original probe suite's unchanged assertion fails with:

```text
Assertion failed: HTTPS TLS timeout retained (actual outcome: Failed; error:
Exception calling "BeginAuthenticateAsClient" with "3" argument(s):
"No credentials are available in the security package")
At tests/Test-Probes.ps1:8 char:28
```

That is a TLS initialization restriction, not a request to collect credentials.
The assertion was not weakened. Historical user-run passes below apply to 0.2.0,
not this edited version.

## New regression coverage

The 23 passing review assertions cover failed DNS, deterministic refused TCP,
TLS validation failure and HTTP 503 with successful evidence collection; preserved
TCP endpoints/TLS stages on ordinary deadline expiry; one shared budget across
stages and slow status-line reads; separate worker/probe timeout summaries; HTML
encoding of every new summary field; and absence of invented diagnoses.

The suite uses real loopback TCP sockets with mocked TLS/HTTP, plus real isolated
workers to verify ordinary probe timeout evidence, hard worker timeout, process
exit, scratch cleanup and continuation. Worker fixtures expire before any external
connection. Mocked orchestration verifies a 2-second probe plus 10-second worker
overhead remains independent of a 1-second passive-check budget. Its report writer
is mocked only for that scheduling test; it does not validate atomic replacement.
HTML generation itself uses the real report writer in a new directory.

## Manual validation from a normal Windows PowerShell terminal

Run from the repository directory, without changing policy. Check each exit code:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
$LASTEXITCODE
powershell.exe -NoProfile -File .\tests\Test-ProbeReview.ps1
$LASTEXITCODE
```

The following is explicitly opt-in and sends external traffic: TCP to 1.1.1.1:443,
A/AAAA queries for example.com against configured DNS servers, and direct HTTPS
HEAD to example.com (each resolved family separately). It inspects configured
gateway neighbours without pinging them:

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -IncludeConnectivityTests -TcpDestinations 1.1.1.1 -TcpPort 443 -DnsQueryName example.com -HttpsEndpoint https://example.com/ -ProbeTimeoutSeconds 10 -ProbeWorkerOverheadSeconds 15 -CheckTimeoutSeconds 30
$LASTEXITCODE
```

Add `-IncludeGatewayPing` to that command only if you also want gateway ICMP.
Open the printed summary.html path. Check CollectionStatus and ProbeOutcome
separately. A zero process exit means the snapshot completed, not that the network
tests succeeded. Raw JSON retains Status/Outcome, errors, completed stages and
observed endpoints. Do not share unredacted diagnostic artifacts.

## Current limitations

No Windows 11 validation or successful IPv6 connectivity validation.
The user-run opt-in snapshot now validates real DNS/TCP/TLS/HTTPS success and
report persistence on Windows 10. The full milestone test suite and original
real TLS timeout suite still need normal-terminal validation of these edits. Earlier different-working-directory
and path-with-spaces entry-point passes below were not repeated for 0.2.1.
Synchronous Windows provider calls (including server-specific Resolve-DnsName)
may not return within the cooperative probe budget; the independent hard worker
deadline remains their ultimate bound. A killed worker cannot supply partial
in-memory evidence and does not establish a network timeout. Extremely slow
startup or result writing can also exhaust the finite worker overhead allowance.

---

# Historical milestone 2 validation

Validation date: 2026-09-23. Environment: **Windows 10 Pro 22H2, build
19045.7725**, **Windows PowerShell 5.1.19041.7725**. Agent-run validations were
non-elevated; the subsequently verified user-run collector recorded elevation.
No Windows 11 validation was performed. The validation runs did not commit or push
repository changes.

## Latest user-run validation: passed

The user supplied normal Windows PowerShell terminal output on 2026-09-23 for
these commands, run from the repository directory:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1
```

The transcript reports **42, 37, and 13 passing assertions (92 total)**. The
default passive collector reports **18 Success, one Unavailable, and one Skipped**.
Exit codes were not included in the supplied transcript, so none are inferred.

The agent independently read the saved JSON from that run and verified schema 2,
collector version 0.2.0, `CollectionStatus=Complete`, populated start/end times,
20 check records, and `IncludeConnectivityTests=False`. The HTML file exists,
and both report files are ignored by Git. The unavailable check explicitly says
the DHCP Client Operational log is disabled. Connectivity was skipped as intended.

The saved collector evidence records **`IsElevated=True`**. This confirms an
elevated user-run collection, unlike the earlier non-elevated agent runs. The
test processes' elevation was not independently recorded. Test passes are
attributed to the user's transcript, not to a new agent-run execution. No new
collection, active external probe, policy change, or restriction bypass was
performed to inspect this evidence. These successful normal-terminal results
do not negate the sandbox failures documented below.

## Earlier sandbox retry after user-confirmed RemoteSigned

Rechecked on **2026-09-23 at 16:32 +01:00** at the user's request. Effective
policy remained RemoteSigned, PowerShell remained 5.1.19041.7725, and the process
was non-elevated. Repeated all four normal `-File` commands below in the sandbox:
the baseline again passed 42 assertions (exit 0); the milestone suite and passive
collector again failed atomic replacement with access denied (exit 1); the probe
suite again failed TLS initialization with "No credentials are available in the
security package" (exit 1). No restrictions were changed or bypassed. The manual
commands below remain applicable.

On 2026-09-23, checked the agent's own sandbox execution context before retrying:

```powershell
powershell.exe -NoProfile -Command 'Get-ExecutionPolicy; Get-ExecutionPolicy -List; $PSVersionTable.PSVersion'
```

Effective policy and CurrentUser were both **RemoteSigned**. MachinePolicy,
UserPolicy, Process, and LocalMachine were Undefined. Windows PowerShell remained
5.1.19041.7725 and the process was non-elevated. Normal file execution and
dot-sourcing were permitted; remaining failures were runtime restrictions, not
script-policy rejections. No restriction was changed or bypassed, and these
latest retries were not rerun outside the sandbox.

| Normal sandbox command | Actual result |
| --- | --- |
| `powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1` | Exit 0; 42 assertions passed. |
| `powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1` | Exit 1; atomic `File.Replace` failed with access denied during checkpoint writes. Full suite did not pass in this retry. |
| `powershell.exe -NoProfile -File .\tests\Test-Probes.ps1` | Exit 1; expected TLS timeout was not reached. `BeginAuthenticateAsClient` failed with "No credentials are available in the security package". This is a TLS initialization failure, not a request to supply credentials. |
| `powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 20` | Exit 1; atomic `File.Replace` failed with access denied. This retry is not a successful end-to-end collection. |

The TLS assertion now includes the actual outcome and error in its failure
message; its pass condition was not weakened. Repeating that test through normal
`-File` execution confirmed the security-package error. Initial evidence from
the failed checkpoint runs remains schema 2, `Incomplete`, with no completion
timestamp and zero completed checks. Generated output remains excluded from Git.

The 92-assertion and end-to-end successes below are **earlier runs outside the
sandbox**, not results of this latest sandbox retry.

### Manual commands from the repository directory

In your normal Windows PowerShell terminal, run the following individually. No
elevation or policy override is requested. Check each exit code before treating a
command as passed; stop and retain the error if any command fails.

```powershell
powershell.exe -NoProfile -Command 'Get-ExecutionPolicy; Get-ExecutionPolicy -List; $PSVersionTable.PSVersion'

powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
$LASTEXITCODE

powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
$LASTEXITCODE

powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
$LASTEXITCODE

powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 20
$LASTEXITCODE
```

Expected assertion counts are 42, 37, and 13 **if each suite succeeds**. The
collector command is passive: active connectivity tests are not enabled. A zero
collector exit code still requires reviewing individual check statuses. Share
pass counts, exit codes, or error messages rather than unredacted diagnostic
reports. The user's subsequent execution of the three test commands and default
collector is recorded above; the exact bounded collector command in this block
was not included in that transcript.

## Execution restrictions and privileges

At the start, normal `-File` execution was blocked and all execution-policy scopes
reported Undefined. Later in the session the host reported CurrentUser
RemoteSigned, with the remaining scopes Undefined. The agent did not change
execution policy, unblock files, supply an execution-policy override, or use
inline source execution as a substitute for running the scripts.

After the observed policy change, the actual test files, entry point, dot-sourced
helpers, and worker scripts executed using `powershell.exe -NoProfile -File`.
Tests requiring atomic replacement and local socket access ran outside the
Codex sandbox, still in a **non-elevated** Windows process. Sandbox permission
and file-sharing failures were not treated as successful tests.

## Test commands and results

From the repository directory:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Snapshot.ps1
powershell.exe -NoProfile -File .\tests\Test-Milestone2.ps1
powershell.exe -NoProfile -File .\tests\Test-Probes.ps1
```

Earlier results outside the sandbox: **92 assertions passed** (42 + 37 + 13).

- The baseline suite covers address classification, observations/hypotheses,
  permission/failure isolation, HTML escaping, JSON/UTF-8 round trips, bounded
  event queries, disabled logs, unsupported providers, and retained event XML.
- The milestone suite starts real worker/child processes, forces a five-second
  timeout, verifies both processes have exited, waits beyond the child's delayed
  write, verifies no late file or worker scratch remains, and then verifies that
  another worker succeeds. It covers explicit argument transfer, worker failure,
  and enum serialization without duplicate JSON keys.
- Mocked full orchestration covers identity, GUID uniqueness, elevation field,
  offset timestamps, incomplete initial/intermediate checkpoints, timeout
  continuation, independent event budgets, NIC-service-derived providers,
  multiple addresses/routes, missing source checks, route/interface metrics,
  active probes disabled by default, and separate IPv4/IPv6 target planning.
- Simulated gateway, DNS, TCP, and HTTPS failures are retained without invented
  root-cause diagnoses. Actual probe function tests mock route/neighbour/DNS
  commands and use loopback-only sockets for closed-port and TLS-timeout cases.
  No external connectivity tests were enabled. Predicted interface 99 is kept
  separate from the observed loopback socket/interface, including after TLS fails.
- Recovery tests interrupt orchestration, read incomplete evidence with completed
  checks, corrupt the primary deliberately, and recover an incomplete backup.
  Hostile identity, parameter, interface, request, and raw-evidence strings remain
  unchanged in JSON and safely encoded in HTML.

All **14 PowerShell source/test files** parsed using the Windows PowerShell 5.1
AST parser. `src/NativeProcess.cs` compiled using Windows PowerShell 5.1 `Add-Type`.
No downloaded test framework or external runtime was used.

## Actual entry-point validation

The real entry point was run from `G:\XZ-TMPDIR`, outside the repository:

```powershell
# $repo is the absolute windows-network-diagnostics repository path.
powershell.exe -NoProfile -File "$repo\Collect-NetworkDiagnostics.ps1" -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 20
```

The entry point and `src/` were also copied beneath the ignored
`output\entry point path with spaces\` directory and executed from the same
external working directory:

```powershell
powershell.exe -NoProfile -File "$repo\output\entry point path with spaces\Collect-NetworkDiagnostics.ps1" -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 20
```

Both runs exercised normal entry-point execution, parent/worker dot-sourcing,
worker argument/path handling, report generation, and incremental writes.
Each reported **18 successful checks, one unavailable disabled DHCP Operational
log, and one skipped connectivity group**. The log remained disabled.

Both final JSON files were read back in Windows PowerShell 5.1 using the actual
dot-sourced `Read-DiagnosticEvidence` helper. Verified schema/state and 20 checks,
disabled active probes, event limits/timestamps/XML, nonempty interface
correlation, absence of script/iframe elements in HTML, and no remaining worker
scratch directories. `git diff --check` passed; all 107 generated files were
verified ignored, and `git ls-files output` returned no tracked output.

## Issues found during validation

- Synced-folder file sharing caused an atomic replacement failure. Added bounded
  retries around the atomic operation, without a delete-then-move fallback, and
  reran the suites successfully.
- A live JSON readback exposed CLIXML-enriched enum objects producing duplicate
  `value`/`Value` keys. Workers now serialize their native result directly to JSON
  before process transfer. Added a worker enum regression assertion and reran
  worker tests and both live entry points.
- A closed loopback port can time out under socket restrictions instead of
  immediately refusing. The test accepts either recorded failure mode and still
  requires no fabricated observed connection. TLS failure is separately tested
  against an actual loopback listener that deliberately does not answer TLS.

## Remaining limitations

- No Windows 11 or non-English locale validation. The user-run collector was
  elevated according to its evidence; test-process privileges in the supplied
  transcript were not independently recorded.
- No external DNS/TCP/HTTPS/ICMP probe run; public-service success, proxy-based
  environments, successful real TLS/HTTP responses, and IPv6 socket success remain
  unverified. Probes are opt-in; this validation used mocks and loopback only.
- No real intermittent DHCP outage, duplicate-IP incident, sleep/resume cycle,
  simultaneous Ethernet/Wi-Fi fault, or complete DHCPv6 lease validation.
- Driver-service-to-event-provider matching is best effort. Unsupported providers
  and the disabled DHCP log limit coverage; the collector does not enable logs.
- Parent hard termination cleanup relies on the Job Object's kill-on-close
  contract; the suite directly tests deadline cleanup and descendant termination,
  not a separate forced parent-process crash.
- JSON and HTML are individually atomic, not an atomic pair. HTML may lag the
  authoritative JSON. Disk exhaustion, power loss during filesystem operations,
  and unsupported filesystems were not fault-injected.
- No browser visual-layout review; HTML correctness was tested through encoding
  and content assertions. Collection is sequential, with no total-run deadline.

Generated live snapshots, failed intermediate runs, synthetic reports, backups,
worker fixtures, and the path-with-spaces validation copy are private files under
ignored `output/`; none are intended for Git. Earlier milestone inline validation
is historical and is not claimed as end-to-end validation here.
