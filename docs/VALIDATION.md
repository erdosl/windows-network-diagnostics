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
