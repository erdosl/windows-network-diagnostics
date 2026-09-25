# Windows network diagnostics

Passive Windows network snapshots and bounded observations for investigating
intermittent addressing, DHCP, DNS, routing and link changes. Collector **0.7.0**
uses artifact **schema 11**. Windows 10/11 and **Windows PowerShell 5.1** are the
support targets; no external runtime dependencies are required.

The tool retains observations and coverage gaps. It does not assign an overall
network-health score or establish root cause. **Competing DHCP servers: not assessed.**

## Start here

Run from the repository in a normal Windows PowerShell terminal using your
organization's approved script-execution process. Do not bypass execution policy.

```powershell
# Passive snapshot
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1

# Bounded passive observation
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 30

# Choose output placement; relative paths use your current directory
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -OutputRoot '.\output\reports [local]'

# Verify a saved run offline: replace <run-directory> with its printed path
powershell.exe -NoProfile -File .\Verify-NetworkDiagnostics.ps1 -Path '.\output\<run-directory>\evidence.json'
```

The run directory prints before collection. Open `summary.html` for the report;
`evidence.json` is canonical evidence. Observation directories also contain sample
JSON files. Reports work offline and remain sensitive local data excluded from Git.

| Workflow | What it provides |
| --- | --- |
| Snapshot | Adapter/address/DHCP/DNS/route/event evidence, local effective DNS policy and global DNS settings, optional baseline and supplied expectations |
| Observation | Bounded samples, stable-GUID field differences, event interval coverage and cumulative-counter comparisons |
| Offline verification | Separate structure, reference and sample-hash results; collection and analysis coverage; no authenticity guarantee |
| Offline capture import | Existing supported capture import and VLAN interpretation; no new external text parser |
| Native capture | Unavailable: existing capability refusal is preserved; no session is started |

Collection `Complete` means planned checks were attempted. Failed checks and
partial analysis remain explicit. A capped event query may omit events even when
its execution succeeded. Policy settings do not prove which DNS resolver an
application used. A route prediction is distinct from an observed socket endpoint.

Active snapshot probes require `-IncludeConnectivityTests`; gateway ICMP also
requires `-IncludeGatewayPing`. Observation never enables probes or capture.

Raw evidence is checkpointed before analysis. Publication failures terminate with
nonzero exit status and preserve earlier checkpoints, samples and recovery backups
when available. Consult the canonical revision and command result if HTML is old.

See the [current reference](docs/CURRENT.md) for parameters, compatibility,
verification, recovery and troubleshooting, and use `Get-Help` on each entry point.
The [validation record](docs/VALIDATION-CURRENT.md) separates test environments and
coverage. [Draft release notes](docs/RELEASE-NOTES-070.md) describe the changes.

## Development and historical evidence

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
```

The default catalog runs no live providers, probes or capture. Results and numbered
recovery checkpoints are under `output/tests/validation-*`. Loopback and live
provider suites require explicit opt-in. No aggregate assertion count is inferred.

Historical [0.6.0 validation](docs/VALIDATION-060.md),
[versioned reference](docs/REFERENCE-HISTORY-060.md),
[implementation history](docs/EVIDENCE-EXTENSIONS.md) and
[Windows 11 findings](docs/WINDOWS11-FINDINGS.md) remain available. Their results
apply to their tested revisions, not this working tree. See [LICENSE](LICENSE).
