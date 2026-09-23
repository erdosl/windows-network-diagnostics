# Milestone 2 validation

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
