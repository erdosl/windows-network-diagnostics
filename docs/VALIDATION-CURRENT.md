# Current validation — 0.7.0 / schema 11

Working tree based on `fde83cf07aa4fc568919272393a7d256d49b122a`.
Actual runner: **Windows PowerShell 5.1.19041.7725**, OS **10.0.19045.0
(Windows 10)**, **non-elevated**. The subsequent normal-terminal user results and
earlier restricted-agent results are separated below. Neither is native Windows 11 validation. No live providers,
network probes, packet capture, policy/permission changes or elevation were used.

## Latest results

The user subsequently ran both the targeted persistence group and the complete
default catalog. **All 15 targeted suites passed; all 43 default suites passed.**
Both saved records have Status Complete, every worker has status Success and
every suite has actual exit code 0. The user separately captured runner exit
code **0** after each command. The records confirm the runtime, OS and privileges
above. Recorded Git HEAD is the base revision; it does not identify uncommitted edits.

No aggregate assertion total is inferred. These user runs preceded the review
correction below; the unchanged full catalog was not repeated by the agent.
The original agent-context failures remain preserved separately.

## Commit review correction and focused validation

Review found that duplicate adapter GUIDs on distinct interface indices could
produce a false field change. Comparison now excludes every ambiguous GUID from
matching while preserving changes for unrelated unique identities. A focused
regression failed before the correction and passed afterward, including the mixed
ambiguous/unique adapter case.

After that correction, actual Windows PowerShell 5.1 execution used:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite Test-ObservationFields,Test-Observation,Test-ObservationModel,Test-Verification,Test-AnalysisIsolation,Test-SourceSyntax,Test-ReliabilityModel
```

All **7 selected suites passed**, worker status Success, suite exits 0 and runner
exit **0**, in the non-elevated Windows 10 environment described above. These are
focused post-review results, separate from the earlier user-run 43-suite catalog.
No persistence code changed during this correction; no live collection was run.

## Earlier implementation validation

Earlier, the restricted-agent complete catalog returned **27 passes and 16 exits 1**.
Fifteen failures were actual atomic `File.Replace` access denial in the restricted
context. One model test had a stale expected named-check list after adding DNS
policy checks. That list was corrected without replacing it with a count-only
assertion; its focused rerun passed. Subsequent focused checks also passed.

Focused agent reruns established **28 passes and 15 persistence suites blocked**.
The later user-run full catalog resolves that outstanding persistence coverage;
it does not relabel restricted-agent failures as passes in that environment.

| Category | Latest outcome | Coverage |
| --- | --- | --- |
| Synthetic, 12 suites | All exit 0 | Existing synthetic suites plus HTTP parsing and observation fields; no sockets |
| Model, 9 suites | All exit 0 in user full run | Analysis isolation, event coverage/cursors, orchestration and report faults; modeled publication explicitly distinguished |
| Worker/entry/offline, 7 suites | All exit 0 | Real workers/serialization, entry/help, verifier, runner recovery and mocked DNS policy with real timeout cleanup |
| Persistence, 15 suites | All exit 0 in both user runs | Real atomic replacement, backups and recovery with synthetic/mocked collectors |

Previously blocked suites, now passed in the user runs: Test-AdapterApipa, Test-CaptureImport, Test-DhcpContext,
Test-DhcpOrchestration, Test-DhcpReview, Test-Dns, Test-EventCorrelation,
Test-LogicalNetwork, Test-LongCheckout, Test-Milestone2, Test-ObservationRun,
Test-PathPortability, Test-ReliabilityPersistence, Test-Snapshot,
Test-SnapshotComparison. Earlier agent logs retain the original access-denied errors.

## Recorded commands

Earlier restricted-agent commands, from the repository directory, actual `.ps1` execution:

```powershell
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -Suite 'Test-AnalysisIsolation,Test-HttpParsing,Test-EventCoverage,Test-ObservationFields,Test-Verification,Test-RunnerRecovery,Test-ReliabilityModel,Test-Observation,Test-ObservationModel,Test-LiveObservation,Test-AdditionalEvidence,Test-SourceSyntax'
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -Suite 'Test-Verification,Test-AnalysisIsolation,Test-DnsPolicy,Test-AdditionalOrchestrationModel,Test-SourceSyntax'
powershell.exe -NoProfile -File tests/Run-Tests.ps1
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -Suite 'Test-Milestone2Continuation,Test-Verification,Test-ObservationFields,Test-SourceSyntax'
```

Runner exits, respectively: **1, 0, 1, 0**. The first run had 11 passes and one
verifier regression: an analysis-error artifact filename was mistaken for a
reference. Explicit exclusion of error payloads corrected it; direct reliability
and later full-run results passed. The second had 5 passes. The full run and final
four-suite rerun are described above. JSON records and bounded suite logs remain
ignored under `output/tests/validation-*/`.

Final review tightened reference diagnostics/types, retained collector provenance
in runner records, and checked unfiltered event-provider inventory and metadata
contract declarations. Only affected suites were rerun:

```powershell
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -Suite 'Test-Verification,Test-RunnerRecovery,Test-SourceSyntax'
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -Suite 'Test-EventCoverage,Test-Verification,Test-SourceSyntax'
```

Both runner commands and all six selected suite executions exited **0**. No second
broad catalog run was performed by the agent. The later user full run is recorded below.

Focused direct invocations during development used
`powershell.exe -NoProfile -File tests/<suite>.ps1` for Test-AnalysisIsolation,
Test-Verification, Test-HttpParsing, Test-EventCoverage, Test-ObservationFields,
Test-RunnerRecovery, Test-ReliabilityModel and Test-DnsPolicy. Latest direct results
were exit 0; earlier harness problems (module autoload replacing a mock and the
built-in Compare alias) were corrected before catalog validation.

## Findings and acceptance coverage

Source review confirmed observation context ran before completion state, rendering
repeated isolated analyses, first-status HTTP classification, missing nested event
coverage, stale HTML publication text, generic non-DHCP differences and end-only
runner persistence. Focused regressions exercise the fixes. The original verifier
accepted underspecified fixtures and missed emitted reference forms; positive
fixtures now come from actual producers with synthetic collectors.

A zero-sample complete observation was verified to be a legitimate startup/deadline
outcome; the verifier deliberately does not require at least one sample.

- Completed and partial serialized samples retain correct empty-configuration
  coverage, raw Pending-analysis checkpoints and matching embedded identities.
- Independent configuration-origin/VPN failures run once, preserve raw evidence,
  permit unrelated analysis and produce safely encoded HTML error context.
- Verifier tests missing completion, invalid types/states, identity/scope errors,
  configuration/VPN/scoped/source/before-after references, unsafe paths, hashes,
  unsupported older schema and raw-provider strings. Real bounded CLI verification
  leaves its canonical input unchanged.
- Synthetic HTTP streams cover informational success/error, multiple interim
  responses, malformed/truncated/EOF/upgrade/byte-line-count limits and timeout.
  Existing optional loopback suites were not run implicitly.
- Event tests cover missing/partial providers, zero events, limit equality,
  retained possible gaps and bounded cursor advancement/deduplication behavior.
- Field tests cover index churn, stable identity, equivalent address spelling,
  order-insensitive records, DNS order, prefix/route/link differences, additions,
  complete removals, missing properties and ambiguous/incomplete inventories.
- Disposable real suite processes cover exit 0, exit 7, timeout with null exit and
  retained partial output, worker cleanup, parent checkpoints and incomplete
  recovery. This validates atomic creation of immutable runner checkpoints, not
  replacement/backups for existing diagnostic artifacts.
- The later user-run persistence suite verifies real checkpoints, backups and
  samples survive all three finalization faults, with actual child commands
  exiting nonzero. Its saved log was checked alongside both results records.
- Mock DNS checks cover namespaces/settings, empty policy, missing capability,
  access failure, real bounded timeout and planned named checks. Installed CDXML
  and Microsoft references were inspected; native provider calls were not run.

Synthetic report markup and evidence links were checked by the existing reporting
regressions. Browser rendering remains **unverified**. No screenshot is claimed.

## Successful normal-terminal user validation

The user executed the targeted group and then the full catalog:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-AdapterApipa,Test-CaptureImport,Test-DhcpContext,Test-DhcpOrchestration,Test-DhcpReview,Test-Dns,Test-EventCorrelation,Test-LogicalNetwork,Test-LongCheckout,Test-Milestone2,Test-ObservationRun,Test-PathPortability,Test-ReliabilityPersistence,Test-Snapshot,Test-SnapshotComparison'
$testExitCode = $LASTEXITCODE
Write-Host "Test runner exit code: $testExitCode"
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
$testExitCode = $LASTEXITCODE
Write-Host "Test runner exit code: $testExitCode"
```

Both runner exits were **0**. The targeted record contains 15 passing persistence
suites. The full record contains 12 synthetic, 9 model, 7 worker and 15 persistence
suites, all passing. The local ignored results and finalization-recovery log were
read back and matched against the supplied transcript; no generated logs are tracked.

No further persistence rerun is requested for the unchanged persistence implementation.
No full Windows 11
collection is requested. Native DNS policy behavior, Windows 11, live probes,
visual browser rendering and new CI remain unvalidated for this working tree.

The successful user-run **37-suite Windows 10** result and successful **Windows
Server CI for fde83cf** are preserved in [VALIDATION-060.md](VALIDATION-060.md),
with provenance and the CI run link. They do not validate 0.7.0. Earlier Windows 11
results concern [older revisions](WINDOWS11-FINDINGS.md).

Private evidence, generated diagnostics, synthetic artifacts and validation logs
remain ignored/untracked. No existing user reports were changed. This record was
prepared before the reviewed commit and push; release notes remain unpublished.

Final `git diff --check` and local documentation-link checks passed. The final diff
and new source/test files were inspected; generated/private paths were not staged.
