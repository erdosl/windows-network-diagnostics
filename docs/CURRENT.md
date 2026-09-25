# Current reference: collector 0.6.0

Windows 10/11 and Windows PowerShell 5.1 are the targets. This release has local
Windows 10 validation with the restrictions in [the current matrix](VALIDATION-CURRENT.md).
The earlier Windows 11 0.5.4 results are historical, not validation of 0.6.0.

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
unchanged configuration. Timing contract 1 is retained: collection uses the parent
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

Root **schema 10** describes an artifact format, not the number of snapshots.
Collector **0.6.0**, `ContextEvidence.ContractVersion=4` and
`ObservationComparisonVersion=4` document the changed lease semantics.
Analysis, publication, metadata and lease timestamp classification use contract 1.
Provider, Wi-Fi, timing and VLAN contracts retain their earlier meanings.

Snapshot baselines in schemas 6–10 are rederived from raw consumed check families;
older derived comparison history is never imported. Older collectors may refuse
schema 10. Observation DHCP states require contract 4 rather than silently
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

The verifier supports schema 10 only, reports older formats as Unsupported,
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
