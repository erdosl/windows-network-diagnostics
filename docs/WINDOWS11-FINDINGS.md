# Windows 11 investigation: collector 0.5.3

## Supplied evidence and limits

The private ZIP paths were inspected for rooted, traversal and drive-qualified
entries before extraction to a fresh ignored `output/tests/` directory. The
screenshot was inspected locally. `windows-11-files/` is now explicitly ignored;
`git ls-files windows-11-files` returned no tracked files. No evidence contents,
machine/run identifiers, adapter identifiers or screenshots were copied into
source or regression fixtures. Existing diagnostic reports were not changed.

The supplied Windows 11 Enterprise Evaluation build 26200 / PowerShell
5.1.26100.9444 runs were non-elevated, collector 0.5.2, schema 9, observation
comparison contract 3. The VM configuration shows four virtual Ethernet adapters;
the supplied inventory has no Wi-Fi adapter. VirtualBox 7.2.16 on Ubuntu 24 is
environment context, not a diagnosed cause. Windows 11 live retesting was unavailable.

The user confirmed that during the Windows 11 snapshot and tests, VirtualBox
Adapter 2 (host-only) was intentionally disconnected; Adapters 1 (NAT), 3 and 4
(internal networks) were connected. These are VirtualBox adapter slot numbers,
not Windows interface indices. This is user-reported test configuration, not
proof of connectivity beyond each link. Adapter 2's disconnected state was
expected and is not itself a fault finding. It does not establish the cause of
the statistics or power-provider failures across the inventoried adapters.

All eight observation hashes matched the manifest; seven samples were complete,
one was useful and partial, and none was empty. The seven pairwise DHCP comparisons
were Unchanged with Complete coverage (13 records per comparison); other assessed
configuration stayed unchanged. Core collection and DHCP comparisons were exercised.
Statistics were unavailable, so no counter rates were established.

## Findings and changes

**Statistics:** all 16 snapshot checks generated AdapterProviderObjectMissing.
Seven completed statistics batches executed successfully but had 16 unavailable
adapter results each; the final batch worker timed out. The old code enumerated
provider rows, then matched only Name. It discarded raw unmatched rows and their
field shapes, so the evidence cannot distinguish empty enumeration from unmatched
rows. No provider or platform root cause is established.

The new code retains query status/scope, row counts, identity values, property
names and match outcomes. It uses exposed InterfaceGuid, exact
InterfaceDescription or exact Name, checks GUID/index/installation-identity
conflicts and inventory ownership, and rejects duplicates. A renamed alias can
match the exact installation identity when no other inventory row owns the alias.
It does not use fuzzy descriptions, array positions or infer GUIDs from opaque
InstanceID strings. The Microsoft [statistics class definition](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapterstatisticssettingdata)
documents Name, InterfaceDescription and opaque InstanceID; InterfaceDescription
is an installation identity. GUID/index are only checked when actually exposed.
One bounded batch enumeration remains; execution success is separate from usable
statistics coverage. Missing counters remain missing.

**Power:** the old code called Get-NetAdapterPowerManagement -Name '*' on every
per-adapter invocation and only filtered after enumeration. Thus the repeated
Windows System Error 31 occurred before successful target attribution, and could
be one source/enumeration failure repeated 16 times. It does not prove 16 devices
malfunctioned. Whether one adapter, the entire provider, permissions or some other
condition caused it is unresolved.

The new snapshot queries use escaped literal names and IncludeHidden, without a
global-enumeration fallback. The installed Windows 10 NetAdapter CDXML declares
RegularQuery AllowGlobbing=true for Name; escaping therefore matters even though
the online [Get-NetAdapterPowerManagement documentation](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterpowermanagement)
parameter table says otherwise. Original native error details and requested scope
survive. Error 31 remains Failed; it is not automatically unsupported, permission
denied or a hardware diagnosis. No elevation requirement was added.

**Wi-Fi:** the old collector treated every nonzero netsh exit as Failed. The
supplied error said wlansvc was not running, alongside an inventory with no Wi-Fi
adapter. New collection queries service state and hidden-adapter capability in
the same bounded worker. Confirmed stopped/absent service or complete no-Wi-Fi
inventory produces Unavailable for expected native exits 0/1, with structured
reason and raw native output. Missing/failed inventory does not prove absence;
unexpected exit codes and access failures stay distinguishable. No service or
adapter state is changed.

**Timing:** scheduling already used Stopwatch and a remaining-budget check before
each worker, including a second guard after initial sample persistence. The old
actual intervals and counter rates, however, used wall-clock subtraction. The
supplied span was 133.6575614 wall seconds for 120 requested seconds, intervals
14.3897382–21.6027725 seconds, and summed worker DurationMs was 112564. That sum
excludes parent work/waits and is not total collection time. The old manifest
cannot establish monotonic overrun or a clock adjustment. VM scheduling, clock
behavior and persistence overhead are unproven possibilities, not conclusions.

Scheduling retains the existing deadline and one-second minimum worker budget.
New timing records collection, finalization, actual same-run monotonic intervals,
termination reason and wall-minus-monotonic difference. Final metadata writes
are explicitly outside the finalization measurement boundary. Per-check DurationMs
is labeled as parent Stopwatch time including startup/cleanup. Counter query
timestamps use the shared system Stopwatch counter with the serialized parent
origin and run ID; unrelated worker origins are never subtracted. Wall-only old
counter intervals are unassessed. Useful partial samples, worker-tree termination,
parent-only atomic persistence and backups are preserved.

Collector version is 0.5.3; schema 9, DHCP comparison contract 3, snapshot context
contract 3 and existing VLAN fixes are preserved. New provider/Wi-Fi/timing/coverage
contracts are version 1; details are in [EVIDENCE-EXTENSIONS.md](EVIDENCE-EXTENSIONS.md).

## Actual Windows 10 validation, 2026-09-24

Windows 10 build 19045; Windows PowerShell **5.1.19041.7725**; non-elevated.
CurrentUser execution policy RemoteSigned; all other scopes Undefined. No policy
override, active connectivity probe, packet capture or network/service modification
was used. Local CIM OS queries returned access denied in this restricted context;
the OS build above comes from Environment.OSVersion, not a successful CIM query.

Each suite below was executed as an actual file from the repository root using
the exact command `powershell.exe -NoProfile -File tests/<suite>.ps1`.

| Suite | Exit / result |
| --- | --- |
| Test-Windows11Evidence | 0; 57 assertions; synthetic providers, controllable clocks and modeled persistence |
| Test-Windows11Worker | 0; 5 assertions; real bounded PowerShell worker, shared clock, serialized inputs, synthetic provider and actual backup recovery reads |
| Test-AdapterApipa | 0; 26 assertions |
| Test-Observation | 0; 13 assertions |
| Test-ObservationDhcp | 0; 17 assertions |
| Test-ObservationSerialization | 0; 25 assertions |
| Test-ObservationModel | 0; 7 assertions, mocked persistence |
| Test-LiveObservation | 0; 29 assertions, synthetic collectors/modeled persistence despite the suite name |
| Test-Snapshot | 0; 42 assertions |
| Test-Presentation | 0; 33 assertions |
| Test-AdditionalEvidence | 0; 15 assertions |
| Test-AdditionalOrchestrationModel | 0; 8 assertions, modeled persistence/collectors |
| Test-DhcpContext | 0; 52 assertions |
| Test-DhcpReview | 0; 41 assertions |
| Test-SnapshotComparison | 0; 54 assertions |
| Test-EventCorrelation | 0; 27 assertions |
| Test-CaptureVlan | 0; 16 assertions, synthetic capture data only |
| Test-EntryLoading | 0; 8 assertions, actual entry help and dot-sourcing from another directory and paths with spaces |
| Test-ObservationRun | 1; File.Replace access denied; real atomic-write orchestration unverified |
| Test-DhcpOrchestration | 1; File.Replace access denied; full orchestration unverified |
| Test-Milestone2 | 1; File.Replace access denied after real worker timeout/descendant cleanup and worker result assertions; later persistence/orchestration/recovery assertions not reached |

Also executed exactly:

```powershell
powershell.exe -NoProfile -File Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 10
powershell.exe -NoProfile -File Watch-NetworkDiagnostics.ps1 -DurationSeconds 10 -IntervalSeconds 5 -CheckTimeoutSeconds 3
git diff --check
git check-ignore windows-11-files output/tests/private-evidence-location.txt
git ls-files windows-11-files
```

Both entry-point runs exited 1 on File.Replace access denied. These are **not**
successful end-to-end collections. No persistence fallback or access-control
bypass was introduced. Diff whitespace checks passed. The ignore checks confirmed
the private evidence and extraction-location file are ignored, with no tracked
private evidence. Real Windows 11 provider success and full persistence in this
development context remain unverified.

Subsequent user-run validation was explicitly on **Windows 10**, Windows
PowerShell 5.1.19041.7725: Test-ObservationRun passed 5 assertions with real atomic
writes, Test-DhcpOrchestration passed 8, and the corrected Test-Milestone2 passed
63; all exited 0. See [the validation follow-up](VALIDATION.md#windows-10-milestone-assertion-follow-up).
These normal-terminal results are separate from the sandbox failures above and
do not replace the pending Windows 11 provider retests.

## Windows 11 read-only retest checklist

1. From the repository on Windows 11, run the two passive entry commands below
   non-elevated. Retain JSON/HTML and their backups privately. Record OS/PowerShell
   versions and exit codes. Do not add connectivity switches.
2. Inspect ProviderDiagnostic: absent rows versus PresentUnmatched, row field
   shapes, MatchBasis, ambiguity/conflicts and QueryFailed. Compare snapshot
   scoped statistics against observation batch coverage. Neither Success on the
   batch nor Unavailable on a row proves device health.
3. Check literal-scoped power errors and original code/category/message. Error 31
   still needs investigation if present; do not elevate or change drivers/services
   merely to suppress the error. Confirm Wi-Fi reasons against service/inventory
   provenance, including failed source checks.
4. Inspect Timing, termination reason, finalization boundary, actual intervals and
   counter query windows. Verify sample hashes and useful partial samples. Preserve
   all unassessed coverage; a selected DHCP server does not assess competing servers.

```powershell
powershell.exe -NoProfile -File .\Collect-NetworkDiagnostics.ps1 -LookbackHours 1 -MaxEventsPerLog 10 -MaxNicEvents 8 -MaxPowerEvents 5 -CheckTimeoutSeconds 10
powershell.exe -NoProfile -File .\Watch-NetworkDiagnostics.ps1 -DurationSeconds 120 -IntervalSeconds 10 -CheckTimeoutSeconds 10
```

For a single problematic adapter, these commands run only bounded, read-only
inventory/statistics/power workers. Choose `$index` from the returned inventory;
it is a same-snapshot selector, not a persistent identity. All output stays private
under output/. No unbounded global power enumeration is necessary.

```powershell
# Run in Windows PowerShell 5.1 from the repository root.
$root = (Get-Location).Path
foreach ($file in 'Core','State','Execution') { . (Join-Path $root "src\$file.ps1") }
$work = Join-Path $root ('output\provider-retest-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory $work
$inventory = Invoke-BoundedCheck ([pscustomobject]@{
    Name='Adapters'; FunctionName='Invoke-SnapshotCollector'; Arguments=@{Name='Adapters'}
}) (Join-Path $root 'src') $work 10
$inventory.Data | Select-Object Name,InterfaceIndex,InterfaceGuid,InterfaceDescription
$index = 7 # Replace with the intended adapter's observed index.
if ($inventory.Status -ne 'Success') { throw 'Adapter inventory unavailable.' }
$target = @($inventory.Data | Where-Object InterfaceIndex -eq $index)
if ($target.Count -ne 1) { throw 'Target missing or ambiguous.' }
$checks = @($inventory)
foreach ($kind in 'AdapterStatistics','AdapterPowerManagement') {
    $checks += Invoke-BoundedCheck ([pscustomobject]@{
        Name=$kind; FunctionName='Invoke-AdapterDetail'; Arguments=@{
            Kind=$kind; AdapterName=$target[0].Name; InterfaceIndex=$index
            InterfaceGuid=$target[0].InterfaceGuid
            InterfaceDescription=$target[0].InterfaceDescription
            AdapterInventory=@($inventory.Data)
        }
    }) (Join-Path $root 'src') $work 10
}
Set-AtomicText (Join-Path $work 'provider-checks.json') (ConvertTo-Json -InputObject $checks -Depth 24)
```

The user subsequently authorized review, commit and push of the pending changes,
including the retained VLAN corrections. Private evidence remains excluded.
