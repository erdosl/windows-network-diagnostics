# Draft release notes — 0.7.0 (unpublished)

These notes describe the 0.7.0 changes based on fde83cf, reviewed for commit and
push. No tag or release is published as part of this change.

## Correctness and verification

- Observation collection state/completion metadata now precede isolated analysis.
  Complete empty configuration has sufficient source coverage; partial samples
  retain incomplete coverage. Embedded context identity matches the sample.
- Configuration-origin and VPN HTML consume stored analysis and failures. Rendering
  does not invoke those analyses again.
- Offline verification validates producer-shaped artifacts, completion metadata,
  types/states/identity relationships and explicitly supported reference forms.
  Raw provider strings are not scanned as references. Structure, references, sample
  hashes, collection completeness and analysis coverage are reported separately.
- Final HTTP responses follow bounded informational responses. Malformed/truncated
  headers and unsupported 101 upgrades cannot become successful probes.
- Event queries expose nested provider coverage and possible capped-interval gaps,
  including after observation cursor advancement.
- Observation HTML describes its evidence revision without stale Rendering or
  publication-in-progress metadata. Publication failures remain terminating.

## Explanations and development workflow

- Observation differences include IP/prefix/state, ordered DNS servers, route
  fields and link state, with stable-GUID associations, before/after evidence and
  interval limitations. Missing evidence does not manufacture removals. Duplicate
  GUIDs on distinct indices remain unassessed; unrelated unique identities can
  still produce assessed changes.
- Validation writes recoverable immutable checkpoints, explicit completion state,
  bounded partial timeout output and actual/unknown exit codes. A catalog audit
  requires intentional categorization of every Test-*.ps1 file.
- README is the concise workflow entry point; current parameters/contracts remain
  in CURRENT.md. The former long README and 0.6.0 validation are preserved as
  historical documents. Browser rendering of synthetic reports is unverified.

## Separate passive DNS policy enhancement

`src/DnsPolicy.ps1` and `tests/Test-DnsPolicy.ps1` contain the new collection/reporting
and focused regressions. Small integration points are in Core, Orchestration,
ReportPipeline and the test catalog. Snapshot-only checks independently collect
local effective NRPT policy and global suffix/devolution settings. Missing commands,
denial and timeout do not look like successful empty policy. No resolver/application
path is inferred and no DNS traffic is sent. Native provider validation is not
claimed from the mocks.

## Compatibility

Collector 0.7.0 uses schema 11 and observation comparison 5. New scoped contracts:
field comparison 1, event coverage 1, DNS policy 1 and validation records 1.
Sample timing 2 makes collection completion before analysis explicit; run timing 1
and counter timing remain unchanged. Context 4, DHCP state 4, lease classification
1, analysis/publication 1 and VLAN behavior are preserved. Baseline schemas 6–11
are rederived from raw consumed families. The verifier explicitly declines older
root schemas; keep original artifacts and their compatible verifier.

Capture import and VLAN interpretation remain implemented. Native capture remains
unavailable under its existing safety refusal. No external tcpdump parser was added.

See [current validation](VALIDATION-CURRENT.md) for exact commands, outcomes,
environment provenance and the successful user-run 43-suite validation. Earlier
restricted-agent persistence denials remain recorded separately.

## Review map

- Stage 1: `src/Observation.ps1`, `src/ReportPipeline.ps1`,
  `src/AdditionalEvidence.ps1`, `src/Verification.ps1`, verifier entry help,
  `tests/Test-AnalysisIsolation.ps1` and `tests/Test-Verification.ps1`.
- Stage 2: `src/Connectivity.ps1`, `src/Events.ps1`, observation/report integration,
  `tests/Test-HttpParsing.ps1` and `tests/Test-EventCoverage.ps1`.
- Stage 3: `src/ObservationComparison.ps1`, observation integration,
  `tests/Test-ObservationFields.ps1`, `tests/Run-Tests.ps1`, `tests/RunnerCore.ps1`,
  `tests/fixtures/SuiteWorker.ps1`, `src/Execution.ps1` bounded scratch-output support,
  `tests/Test-RunnerRecovery.ps1`, README and current/historical documentation.
- Stage 4: `src/DnsPolicy.ps1`, `tests/Test-DnsPolicy.ps1`, and the explicitly named
  snapshot scheduling/report/catalog integration points described above.
- Compatibility/support: `src/State.ps1`, `src/Core.ps1`, `src/DhcpContext.ps1`,
  `src/Orchestration.ps1`; version assertions in Test-Milestone2,
  Test-AdditionalOrchestrationModel, Test-DhcpOrchestration, Test-ReliabilityModel
  and FinalizationFault; named expectations in Milestone2Orchestration and its
  continuation test. No capture/import/VLAN implementation files were changed.
