# Windows 11 follow-up completed: collector 0.5.4 (2026-09-25)

## Evidence available for this review

The ignored `windows-11-files/` directory currently contains only `queries.json`.
The latest 0.5.3 snapshot/observation ZIPs, `adapters.txt` and a saved console
transcript are absent. No ZIP was extracted or read during this review. Earlier
archive findings below are preserved as previously verified evidence, not newly
recomputed sample counts, hashes or timings. The four latest suite results and
inspector exit code come from the user's supplied report.

The inspector JSON is Complete, collector **0.5.4**, contract **1**, non-elevated,
with Windows build **10.0.26200.0** and Windows PowerShell **5.1.26100.9444**.
The supplied environment is Windows 11 Enterprise Evaluation in VirtualBox
7.2.16 on Ubuntu 24. Coverage is limited to this VM, build, runtime and query
scope; Windows 10 development results are recorded separately in
[VALIDATION.md](VALIDATION.md#windows-11-follow-up-2026-09-25-collector-054).
No private identities or report records are copied into tracked documentation.

## Current provider observations and unresolved causes

| Inspector query | Status | Returned rows / result |
| --- | --- | --- |
| DefaultAdapters | Success | 4 |
| HiddenAdapters | Success | 16 |
| CimAdapters | Success | 4 |
| Adapters (collector) | Success | 16, including all eight WAN miniports |
| WildcardStatistics | Success | 0 |
| UnfilteredStatistics (omitted Name) | Success | 0 |
| CimStatistics | Success | 0 |
| AdapterStatistics (selected WAN Miniport (IP)) | Unavailable | Native `CmdletizationQuery_NotFound_Name` / ObjectNotFound |
| AdapterPowerManagement (same selected adapter) | Failed | `Windows System Error 31,Get-NetAdapterPowerManagement` |

**Inventory discrepancy did not reproduce.** Direct comparison of native
hidden-inclusive and collector rows found 16 unique GUIDs in each, with zero
differences in normalized GUID, interface index, exact alias and description.
Both contain all eight WAN miniports, whose aliases contain literal asterisks.
Queries were sequential, not simultaneous. Raw CIM returning four rows does not
invalidate hidden-inclusive enumeration: their scopes may differ.

The earlier 0.5.3 eight-adapter snapshot/observation result remains unexplained.
No collector fix, wildcard defect, clock issue or guest-state change has been
established as the cause of the difference. The earlier code review found the
inventory invocation unchanged: `Get-NetAdapter -IncludeHidden -ErrorAction Stop`
followed by projection, without a Name filter or adapter exclusion. Literal
escaping applies to detail queries after inventory. The 40 synthetic inventory
assertions and this native inspector run demonstrate preservation in their tested
scopes, not what the native provider returned during the earlier collection.

**Statistics absence extends beyond collector identity matching.** Wildcard,
omitted-Name and raw CIM enumeration all succeeded with zero rows. There are no
returned rows for matching to recover in this run. The selected literal query
retains its native NotFound_Name error and `LiteralAdapterName` scope; its exposed
NativeErrorCode is null. This evidence does not establish an unsupported, broken,
permission-limited or VirtualBox-defective provider. No counter rates were validated.
Successful query execution is separate from usable counter coverage.

**Scoped power Error 31 persists.** The selected WAN Miniport (IP) query is Failed,
with `LiteralAdapterName` scope and the Windows error identifier above. Its
`Microsoft.Management.Infrastructure.CimException` exposes NativeErrorCode **1**,
which is distinct from Windows error **31** in the identifier. The original
message and error fields remain in private evidence; NativeErrorCode is not a
parsed Windows error number. This targeted result does not diagnose hardware
faults across adapters. The underlying cause remains unresolved. Earlier 0.5.3
literal power failures are historical evidence, not additional targets tested
by this inspector.

## Confirmed Windows 11 portability validation

The user reports all four targeted suites exited **0**: Test-ObservationRun
(**5** assertions, mocked collectors and real atomic writes), Test-DhcpOrchestration
(**8**), Test-PathPortability (**6**) and Test-InventoryBoundaries (**40**, synthetic
providers and real worker serialization). Total: **59** assertions. Source review
of Test-PathPortability confirms its printed **4** is an intermediate checkpoint
within the final **6**, not four additional assertions.

The reported portability output says "Legacy long temporary creation failed on
this runtime." Revised first publication, atomic replacement, backup preservation
and temporary cleanup passed. This supplies real Windows 11 validation of the
shorter atomic temporary basename and orchestration persistence. It does not
establish universal long-path support or that every DirectoryNotFoundException
is caused by path length. The suite accepts either PathTooLongException or
DirectoryNotFoundException for the legacy experiment; the reported line alone
does not identify which occurred.

The exact checkout path for these four tests is not established. The later
provider inspector was run from a single-level downloaded checkout; that does
not prove the four tests ran there or in the original doubly nested checkout.
Latest suite elevation and execution-policy settings are not recorded separately.
The inspector JSON establishes non-elevated execution only for its own run.

Historical Windows 10 sandbox File.Replace access denials remain recorded in
VALIDATION.md. Those failures and the subsequent Windows 11 user-run successes
are distinct results. No access-control workaround or weaker persistence is implied.

## Preserved 0.5.3 snapshot and observation evidence

The previous review verified a Complete passive snapshot with eight adapters and
eight observation samples: **seven Complete, one useful Incomplete, none empty**,
each with eight adapters. **All eight hashes matched.** The user reported exit
**0** for both passive entry runs. Wi-Fi was correctly
**Unavailable/WlanServiceStopped**.

Monotonic collection elapsed was **119.661219 seconds**; finalization was
**0.1664396 seconds**, excluding final metadata writes. Wall-minus-monotonic
collection difference was **0.0043927 seconds** (approximately **4.4 ms**).
These measurements describe that run only. The missing ZIPs prevent independent
reverification in this documentation review; the inspector JSON cannot substitute
for observation artifacts. Earlier `adapters.txt` findings are likewise historical.

## Follow-up status and scope

The latest targeted Windows 11 follow-up is **completed**. See
[the supplied validation record](VALIDATION.md#completed-targeted-windows-11-follow-up-054)
for commands and provenance. No additional full snapshot or observation is
currently required for these documentation changes. Provider causes remain open;
any future investigation should be driven by new evidence rather than a presumed
collector defect. A selected DHCP server and successful client probes do not
assess competing DHCP servers on the LAN.

Collector **0.5.4** was already committed and pushed before this review. Root
schema **9**, context **3**, DHCP observation comparison **3**, and provider/Wi-Fi/
timing contracts **1** are unchanged. This review changes documentation only;
no collector behavior, versions, probes, capture or network settings were changed.
Private evidence remains ignored and untracked; existing reports are untouched.
The initial documentation review left changes uncommitted and unpushed; the user
subsequently authorized review, commit and push.

# Historical Windows 11 investigation: collector 0.5.3

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
did not establish Windows 11 provider behavior; see the completed follow-up above.

## Historical Windows 11 read-only retest checklist (superseded)

The subsequent 0.5.3 passive runs and completed 0.5.4 targeted follow-up above
supersede this checklist. These commands are retained as historical context;
another snapshot or observation is not currently required.

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
