# Current reference: collector 0.7.0

Windows 10/11 and Windows PowerShell 5.1 are the targets. See local
Windows 10 validation coverage and restrictions in [the current matrix](VALIDATION-CURRENT.md).
The earlier Windows 11 0.5.4 results are historical, not validation of 0.7.0.

## Collection, analysis and publication

Snapshot collection checkpoints raw checks before and after each attempted check.
Raw checkpoints have pending analysis and cleared derived values. At finalization,
each analysis family runs once; failures are retained in `Analysis.Sections`,
while other families continue. JSON containing analysis is published before HTML.
`Analysis.EvidenceRevision`, each section's revision and HTML's revision identify
their input. There is no claim of measured speed improvement.

Observation saves each completed check before sample analysis. DHCP context,
configuration changes and counter deltas are separate analysis sections. Samples
retain interface values, source coverage and structured historical event context;
the manifest links samples and summarizes changes. Manifest statistics coverage
uses an explicit Artifact name to scope its EvidencePath to the sample. Failed analysis never means
unchanged configuration. Sample timing contract 2 ends collection before analysis; run timing contract 1 is retained: collection uses the parent
Stopwatch, counter intervals require same-run monotonic windows, and finalization
measurement excludes final metadata writes. The initial HTML publication is in
the measured finalization interval; the final metadata/HTML writes are outside it.

`CollectionStatus=Complete` means planned checks were attempted, not that they
succeeded. `Analysis.Status` and `Publication` are separate. A status serialized
inside an artifact describes its generation attempt; only the command's successful
return confirms final publication. An older HTML report or backup can survive a
newer failed publication. Always compare revisions and consult canonical JSON.

| Command result | Meaning |
| --- | --- |
| Snapshot/observation exit 0 | Requested final JSON and HTML published; inspect collection, analysis and individual check outcomes |
| Snapshot/observation exit 1 (terminating error) | Collection orchestration, JSON serialization, canonical publication or requested HTML failed; prior artifacts may remain recoverable |
| Analysis Partial/Failed with exit 0 | Raw evidence and a report of analysis limitations published; failed sections are null/empty with error records, never stale results |
| Verifier exit 0 | Supported artifact passed implemented structure/reference/hash checks |
| Verifier exit 1 | Invalid, incomplete, unsupported, timed out or unreadable artifact; inspect returned worker/result status |

Canonical persistence failures are fatal. Original exceptions and artifact paths
remain in error context; observation retains both collection and finalization
errors when both fail. HTML failure attempts to publish failure metadata separately;
if that write also fails, its error is retained in the exception. There is no claim
that failure metadata reached disk. Neither failure deletes samples or backups.

## Output, parameters and progress

Both collection entry points accept `-OutputRoot`. The default remains the
repository's `output/`. Relative paths resolve against the caller's current
working directory. Spaces and literal brackets are supported. Each run creates
a unique directory; existing run directories are refused. A run-local `.gitignore`
excludes generated files even when a custom output root is inside a Git worktree. Output failure never
silently redirects reports. Atomic temporary files remain beside their destination.

Workers use unique private scratch directories under
`%TEMP%\output\tests\network-diagnostics-workers`, separate from reports. A Windows
job object bounds each worker and its descendants, with cleanup after termination.
The parent alone publishes canonical reports. The run directory prints early;
progress says which check is running, without adding success-stream result objects.

| Entry | Main parameters |
| --- | --- |
| `Collect-NetworkDiagnostics.ps1` | `OutputRoot`, `PreviousSnapshotPath`, `ExpectationsPath`, `IncidentContextPath`, `LookbackHours` (1–168), separate network/NIC/power event limits, `CheckTimeoutSeconds` (1–600) |
| Explicit snapshot probes | `IncludeConnectivityTests`; gateway ICMP also requires `IncludeGatewayPing`; legacy DNS targets also require `IncludeLegacyDnsTargets`; existing interface/source and probe-budget parameters remain |
| `Watch-NetworkDiagnostics.ps1` | `OutputRoot`, `DurationSeconds` (10–600), `IntervalSeconds` (5–120), `CheckTimeoutSeconds` (1–60), `IncidentContextPath`; passive only |
| `Verify-NetworkDiagnostics.ps1` | `Path` to canonical evidence JSON, `TimeoutSeconds` (1–120, default 30); offline only |
| `tests/Run-Tests.ps1` | Optional `Suite` names (array or comma-separated); per-suite timeout; loopback and live-provider categories require explicit switches |

Use `Get-Help .\Collect-NetworkDiagnostics.ps1 -Full` or the other entry names
for examples and the complete parameter list. Examples from another directory:

```powershell
powershell.exe -NoProfile -File 'C:\Tools\Network diagnostics\Collect-NetworkDiagnostics.ps1' -OutputRoot '.\output\reports [local]'
powershell.exe -NoProfile -File 'C:\Tools\Network diagnostics\Watch-NetworkDiagnostics.ps1' -DurationSeconds 30 -OutputRoot '.\output\reports [local]'
powershell.exe -NoProfile -File 'C:\Tools\Network diagnostics\Verify-NetworkDiagnostics.ps1' -Path '.\output\reports [local]\<run-directory>\evidence.json'
```

Replace `<run-directory>` with the directory printed by collection. No probe or
capture is enabled by these examples. Native capture still refuses to run unless
its existing narrow-filter/session-ownership guarantees can be satisfied.

## DHCP interpretation and compatibility

Root **schema 11** describes an artifact format, not the number of snapshots.
Collector **0.7.0**, `ContextEvidence.ContractVersion=4` and
`ObservationComparisonVersion=5` identify unchanged DHCP context semantics and expanded non-DHCP comparisons.
Analysis, publication, metadata and lease timestamp classification use contract 1.
Provider, Wi-Fi, run/counter timing and VLAN contracts retain their earlier meanings; sample timing is now contract 2.

Snapshot baselines in schemas 6–11 are rederived from raw consumed check families;
older derived comparison history is never imported. Older collectors may refuse
schema 11. Observation DHCP states require contract 4 rather than silently
comparing older derived states. Preserve original artifacts when upgrading.

Valid timestamps compare as instants. Equivalent offsets produce `SameInstant`.
Only assessed forward progression becomes `LeaseRefreshed` (snapshot presentation:
`Lease refreshed`). Backward movement is `Changed/BackwardMovement`; clearing is
`Changed/Cleared`; a previously absent timestamp becoming valid is
`Changed/BecameAvailable`. Invalid timestamps are unassessed. Explicit null/empty,
missing properties and unavailable sources remain distinct. Raw representations
remain in raw checks and lease comparison details. A timestamp progressing does
not establish that a DHCP exchange was captured.

Assessed configuration changes survive missing fields and ambiguous other adapters.
Stable GUID matching and host validation remain required; alias/index/MAC alone
cannot establish cross-snapshot continuity. Disconnected interfaces remain visible.
Structured Windows event associations preserve exact, ambiguous, historical-only
and unmatched cases, source intervals and references. Proximity is not cause.
**Competing DHCP servers: not assessed.** Expectations are supplied policy,
not a detector for simultaneous competing servers. No Ubuntu tcpdump transcript
or external capture parser is used for these conclusions.

For a reproducible synthetic baseline/expectations example, run:

```powershell
powershell.exe -NoProfile -File .\examples\New-SyntheticContext.ps1
```

The example writes new fixtures only under `output/tests/`, prints their paths,
and demonstrates comparison without running collectors or probes. Synthetic host
identity deliberately prevents using that baseline as a real host's baseline.

## Metadata and offline verification

`Metadata` identifies collector, mode, run, runtime and applicable contracts.
Runtime OS version is attributed to `System.Environment.OSVersion`, including
its compatibility caveat. Snapshot Windows-provider status/reason and reference
are separate, including provider denial. Observation does not add an OS provider
query. An optional, at-most-4096-byte `src/BuildInfo.json` can provide a packaged revision
with matching CollectorVersion and a 40-character hexadecimal Revision; it does
not certify unmodified local files. Build revision is otherwise explicitly unavailable: no revision is embedded in this
source tree, no Git dependency is introduced, and ZIP downloads get no invented SHA.
The test runner records Git HEAD when available and labels possible working edits.

The verifier supports schema 11 only, reports older formats as Unsupported,
and reads in a bounded Windows PowerShell worker. Limits: 32 MiB per JSON file,
128 MiB total, 121 samples, reference traversal depth 48. Only expected sequential
sample basenames in the artifact directory are allowed; remote paths, traversal,
alternate streams and sample reparse points are rejected. It checks run/metadata
identity, applicable contracts, scoped JSON references, sequence, sample status
and recorded SHA-256 hashes. No files are rewritten, collected or sent over the
network. Missing hashes on partial runs remain an explicit verification failure.
Integrity checks are not authenticity: matching hashes do not identify an author.

## Troubleshooting

- Downloaded scripts: use your organization's approved signing/execution process.
  Do not change policy or bypass restrictions to obtain a pass.
- Long checkout paths: select a shorter `OutputRoot` with room for run directories,
  temporary files and backups. This is not universal long-path support. A
  DirectoryNotFoundException alone does not diagnose path length.
- Persistence denial: retain the exception, last canonical checkpoint, `.bak`
  and sample files. Do not delete reports or weaken atomic replacement. Reproduce
  with the narrowly scoped persistence suites in a normal approved terminal.
- Unavailable providers: inspect structured status and native error provenance.
  Missing rows are not hardware faults. CIM NativeErrorCode is distinct from a
  Windows error number in an identifier; Error 31 does not prove unsupported
  hardware. Localized message wording does not determine access-denied status.

Historical implementation and validation notes remain in
[EVIDENCE-EXTENSIONS.md](EVIDENCE-EXTENSIONS.md), [VALIDATION.md](VALIDATION.md) and
[WINDOWS11-FINDINGS.md](WINDOWS11-FINDINGS.md). Their version-specific statements,
including historical commit status, do not describe this working tree.

## Effective DNS policy (separate passive enhancement)

Snapshot checks `DNS:EffectivePolicy` and `DNS:GlobalSettings` run independently in
bounded workers. They collect local `Get-DnsClientNrptPolicy -Effective` namespaces,
name servers, DirectAccess and DNSSEC/query settings, and
`Get-DnsClientGlobalSetting` suffix search list, devolution enablement and level.
Selected settings retain missing-field metadata and explicit cmdlet provenance.
Successful empty policy is `ObservedEmpty`; unsupported, denied, failed and timed-out
checks remain distinct. No observation sampling, network query, PAC retrieval,
remote session or setting change is performed. Policy does not establish the
resolver actually used by a particular application.

Field selection follows Microsoft's [NRPT cmdlet reference](https://learn.microsoft.com/en-us/powershell/module/dnsclient/get-dnsclientnrptpolicy)
and [global settings reference](https://learn.microsoft.com/en-us/powershell/module/dnsclient/get-dnsclientglobalsetting),
and was checked against installed Windows 10 CDXML definitions without executing
native policy queries. DNS policy/settings payload contract is 1.

## Current comparison, event and verification details

Observation comparison 5 adds field-comparison contract 1: IP address/prefix/state,
DNS lists (order retained), route destination/next hop/metrics and adapter link
state. GUIDs associate adapters; indices only select records within each sample.
Order-insensitive record collections and equivalent IP spellings do not create
changes. Missing fields, duplicate identities and incomplete sources retain
uncertainty; absent records become removals only with sufficient complete evidence.
Changes include before/after sample pointers and the interval between sample starts.
No continuity or event causation is inferred.

Event coverage contract 1 distinguishes query execution, provider availability,
requested interval, returned count and limit. Limit equality is a possible gap,
not proven truncation. The cursor advances without replaying the interval; the
original interval and coverage limitation remain in sample and manifest summaries.

HTTPS probes consume at most eight informational responses before a final 200–599
response. HTTP 101 is unsupported. One timeout spans TCP/TLS/HTTP; header parsing
is bounded to 32768 bytes total and 4096 bytes per line. Truncation or malformed
headers fail the probe while completed stages and received statuses remain in
its evidence. There is no redirect following, authentication or body download.

Verification uses schema-aware reference-bearing sections, excluding raw provider
payloads. `Structure`, `References`, `SampleHashes`, `CollectionStatus` and
`AnalysisCoverage` are separate. Complete collection with partial analysis can
verify successfully; incomplete collection returns `Incomplete` if the other
checks pass. A valid zero-sample completed observation is allowed because the
startup/deadline budget can prevent an attempted sample. Root/sample completion
metadata and embedded identities must agree. Schema 10 and older artifacts are
explicitly Unsupported by this verifier; baseline reading still supports 6–11.

The validation runner writes an initial Incomplete record and immutable numbered
atomic checkpoints before/after suites. Earlier checkpoints are never replaced.
`results.json` is the final record for normal completion or a caught interruption;
a killed parent may leave only checkpoints. Choose the highest complete numbered
JSON file and inspect its Status and PendingSuite. Worker scratch retains up to
65536 output characters; the parent publishes the log after worker cleanup,
including on timeout. Missing exit code is null, never an inferred success/failure
code. Catalog validation rejects uncategorized Test-*.ps1 files.
