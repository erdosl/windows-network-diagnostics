# Current validation: 0.6.0 / schema 10

2026-09-25, working tree based on `a0cab8c`. Actual local environment: Windows 10
build **10.0.19045.0**, Windows PowerShell **5.1.19041.7725**, non-elevated.
CurrentUser policy is RemoteSigned; other scopes are Undefined. No policy override,
elevation, live provider query, connectivity probe, capture or network change was
performed. All suites ran as actual `.ps1` files in `powershell.exe` processes.
The outer tool shell was not treated as Windows PowerShell validation.

## Latest observed suite outcomes

The subsequent user-run full catalog passed **all 37 suites**, each with worker
status Success and exit code 0. The user separately captured the runner's
`$LASTEXITCODE` as **0**. The saved results confirm Windows PowerShell
5.1.19041.7725, OS 10.0.19045.0 and non-elevated execution against the working
tree based on `a0cab8c`; that HEAD does not identify the uncommitted edits.
No aggregate assertion total is inferred from console messages.

| Category | Suites (each `.ps1` under `tests/`) | Latest exit / coverage |
| --- | --- | --- |
| Synthetic | Test-AdditionalEvidence, Test-CaptureVlan, Test-InterfaceProbes, Test-Observation, Test-ObservationDhcp, Test-ObservationSerialization, Test-Presentation, Test-LeaseReliability, Test-ErrorClassification, Test-SourceSyntax | Each 0; fixtures/mocked providers, no live probes or capture. Syntax parsing is additional coverage, not a replacement for script execution |
| Model | Test-AdditionalOrchestrationModel, Test-ObservationModel, Test-LiveObservation, Test-CaptureEvidence, Test-Milestone2Continuation, Test-Windows11Evidence, Test-ReliabilityModel | Each 0; modeled persistence/collectors. Some use actual child scripts; no atomic replacement claim |
| Worker / entry / offline | Test-Windows11Worker, Test-InventoryBoundaries, Test-EntryLoading, Test-OutputPlacement, Test-Verification | Each 0; real bounded worker/serialization or real entry/help execution. Providers are synthetic; verifier fixtures use ordinary test-file writes, not an atomic-write substitute |
| Real persistence | Test-AdapterApipa, Test-CaptureImport, Test-DhcpContext, Test-DhcpOrchestration, Test-DhcpReview, Test-Dns, Test-EventCorrelation, Test-LogicalNetwork, Test-LongCheckout, Test-Milestone2, Test-ObservationRun, Test-PathPortability, Test-ReliabilityPersistence, Test-Snapshot, Test-SnapshotComparison | Each 0 in the user-run full catalog; real atomic I/O, synthetic/mocked providers |

Earlier restricted-agent results were **22 passes and 15 persistence suites
blocked by File.Replace denial**. Those failures remain historical observations
of that environment; they were not rerun or relabeled as agent-context passes.
The later normal-terminal run resolves the outstanding persistence validation.

The initial catalog run attempted 36 suites and returned 1 (17 passes, 19
failures). Review corrected old assertions expecting schema 9, analysis in the
initial raw checkpoint, English-message-only permission classification, and a
null-to-valid lease timestamp being called a refresh. The verifier fixture suite
was separated from unrelated atomic-write requirements; its ordinary fixture
writes are explicitly labeled. A new syntax suite brings the catalog to 37.
Focused restricted-agent reruns established the earlier 22-pass outcome. The reliability model's two-sample
test also needed an explicit five-second interval; that harness error was fixed.

## Commands and records

Latest user-run command, from the repository directory:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
$testExitCode = $LASTEXITCODE
Write-Host "Test runner exit code: $testExitCode"
```

Runner exit **0**; **10 synthetic, 7 model, 5 worker and 15 persistence suites
passed**. The local ignored `results.json` and reliability-persistence log were
read back and checked against the supplied transcript. Generated records remain
under `output/tests/validation-*/` and are not included in Git.

Earlier restricted-agent commands, from the repository directory:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityModel,Test-LeaseReliability,Test-ErrorClassification,Test-OutputPlacement,Test-Verification,Test-ObservationDhcp,Test-LiveObservation,Test-AdditionalOrchestrationModel,Test-Windows11Evidence,Test-ObservationModel,Test-ObservationSerialization,Test-InventoryBoundaries,Test-Windows11Worker,Test-EntryLoading,Test-Milestone2Continuation'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-SourceSyntax,Test-ReliabilityModel,Test-LeaseReliability,Test-ErrorClassification,Test-Verification,Test-Windows11Evidence,Test-ObservationModel,Test-LiveObservation,Test-OutputPlacement'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityModel,Test-SourceSyntax,Test-ErrorClassification,Test-DhcpOrchestration,Test-Snapshot,Test-ReliabilityPersistence,Test-ObservationRun,Test-Verification,Test-Windows11Evidence'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityModel,Test-LongCheckout,Test-SourceSyntax,Test-LeaseReliability,Test-ErrorClassification,Test-Verification'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityModel,Test-Verification,Test-SourceSyntax,Test-Windows11Evidence'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityModel,Test-Verification,Test-SourceSyntax,Test-Windows11Evidence,Test-ReliabilityPersistence'
powershell.exe -NoProfile -File .\examples\New-SyntheticContext.ps1
```

Runner exit codes in that order: **1, 0, 1, 1, 1, 0, 1**. The third invocation still
contained the interval test-harness failure; later runs corrected it. The example
exited **0**, using synthetic input only. Individual suites also had focused direct
`powershell.exe -NoProfile -File tests/<suite>.ps1` executions during development;
the final direct reliability-model result was successful. Runner records retain
each actual command, exit code, elapsed duration, category, mock boundaries,
runtime, OS, elevation and available Git HEAD. Output is ignored under
`output/tests/validation-*/`; no private local paths or artifact IDs are tracked.

Final focused checks after review:

```powershell
powershell.exe -NoProfile -File .\tests\Test-OutputPlacement.ps1
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-SourceSyntax,Test-OutputPlacement,Test-EntryLoading,Test-ReliabilityModel,Test-Verification'
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-OutputPlacement,Test-SourceSyntax'
```

Each command exited **0**; each selected suite exited **0**. A stronger help
assertion exposed adjacent `#requires` comments preventing comment-based help
recognition. Blank-line separation corrected it. The final placement suite checks
actual `-?` command exits and recognized help examples for all four changed entry
points, plus generated-artifact Git exclusions in custom output directories.

## Focused acceptance coverage

- Final-publication injection occurs after modeled checkpoints and samples.
  Actual child `.ps1` processes exit nonzero for canonical JSON, HTML and combined
  collection/finalization failures. Original exceptions, paths and both errors
  survive. The real-persistence equivalent passed in the later user run: actual
  checkpoints, backups and samples survived all three injected finalization
  faults, and child commands exited nonzero. Its earlier restricted-agent run
  stopped at File.Replace denial and was not counted as fault-injection coverage.
- Raw snapshot checks survive analysis exceptions; other analysis families finish.
  Invocation counts show one final analysis/render pass, not a performance timing
  claim. Sample comparison failure leaves raw checks and other analysis sections
  intact, with no stale change values. Serialization and canonical I/O faults
  have distinct stages. Baseline source references resolve in raw checkpoints.
- Shared lease tests cover equivalent offsets, forward, backward, cleared and
  malformed values in snapshot and observation comparisons; missing fields retain
  other assessed changes. Ambiguous identities and structured event references
  remain explicit with interval/noncausal limitations.
- Actual entry copies in a path with spaces execute from another working directory.
  Disposable orchestration stubs verify OutputRoot forwarding, relative paths,
  literal brackets and run-directory collision refusal without collection.
- Offline verifier tests exercise valid snapshot/observation fixtures, missing
  references, bad hashes, unsafe sample paths, older contracts, and real bounded
  command exit codes. The canonical input hash is unchanged after verification.
- Populated synthetic HTML was inspected as markup: first-screen statuses,
  configuration changes, lease classification, policy mismatch, encoded aliases,
  expandable raw evidence and all local evidence anchors were checked. The browser
  URL policy rejected local-file preview; visual rendering remains unverified.

## Remaining validation

The full user run includes the previously requested narrow persistence group;
no repeat is needed for the unchanged implementation. For a future targeted
regression run after relevant changes:

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -Suite 'Test-ReliabilityPersistence,Test-ObservationRun,Test-DhcpOrchestration,Test-PathPortability,Test-Snapshot,Test-DhcpReview,Test-SnapshotComparison'
```

Do not bypass execution restrictions or weaken File.Replace to obtain a pass.
No new full Windows 11 snapshot or observation is requested. Existing
[Windows 11 results](WINDOWS11-FINDINGS.md) concern 0.5.4 and earlier, not this
implementation. Live native-provider behavior, elevated execution and physical
network behavior have not been revalidated. Native capture remains unavailable
under the existing capability refusal.

The new [Windows CI workflow](../.github/workflows/windows-powershell.yml) selects
`windows-2022` and explicitly uses Windows PowerShell, following
[GitHub's shell documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell).
It runs non-live suites and saves their validation records. CI had **not run** at
the time of this local validation record. A Windows Server runner result must be labeled with its
actual recorded OS and must not be called Windows 10 or Windows 11 validation.

`git diff --check`, local documentation links, private/generated-artifact exclusions
and the diff were reviewed. No existing user reports were changed. These results
were recorded before commit and push. See [historical validation](VALIDATION.md) separately.
