# Windows 11 follow-up: collector 0.5.4 (2026-09-25)

## Current evidence and conclusions

The two latest ZIPs and `adapters.txt` were available in the ignored
`windows-11-files/` directory. Every ZIP entry was checked for rooted paths,
drive qualifiers and traversal before reading. JSON was read directly from the
archives in memory; no extraction was necessary. No private identifiers were
copied into source or fixtures. The older 16-adapter 0.5.2 results below are
historical evidence, not a comparison against the Windows 10 development host.

The latest Windows 11 0.5.3 snapshot is Complete with eight adapters. All eight
observation sample hashes match: seven Complete, one useful Incomplete, none
empty, each with eight adapters. Collection elapsed is 119.661219 seconds;
finalization is 0.1664396 seconds excluding final metadata writes; wall minus
monotonic collection is 0.0043927 seconds. The supplied passive snapshot and
observation each exited 0. Wi-Fi remains correctly Unavailable/WlanServiceStopped.
These behaviors and all timing code are preserved.

The environment remains Enterprise Evaluation build 26200, Windows PowerShell
5.1.26100.9444, VirtualBox 7.2.16 on Ubuntu 24. NAT and both internal-network
adapters were connected; the host-only adapter was intentionally disconnected.
Windows 11 live retesting is unavailable until the user returns to that environment.

**Inventory cause unresolved.** The direct text confirms four default and 16
hidden-inclusive adapters. The eight additional rows are the WAN miniports IP,
Network Monitor, SSTP, L2TP, IKEv2, PPTP, IPv6 and PPPOE, whose aliases contain
literal asterisks. Other hidden/not-present rows are retained by the collector.
The direct query was later, so guest/provider state changes remain possible.

Tracing the 0.5.2-to-0.5.3 diff establishes that the inventory invocation did not
change: `Get-NetAdapter -IncludeHidden -ErrorAction Stop` followed by field
projection. There is no Name filter, shared literal-query helper, description
deduplication or state exclusion in this path. The orchestrators retain the
Adapters check rows. CLIXML serializes explicit worker inputs; worker JSON
serializes all returned rows. Escaping occurs only in `Invoke-AdapterDetail`,
after inventory, for statistics and power. Installed Windows 10 generated CDXML
code filters Name only when that parameter is bound. Its Name query supports
globbing, so escaped literal targeting is appropriate; spaces need no escaping.
This local metadata does not prove identical Windows 11 provider behavior.

Forty new synthetic assertions verify unfiltered inventory, 14 distinct ordinary,
wildcard-character, hidden WAN and not-present tunnel rows, similar descriptions,
real worker serialization, literal statistics/power boundaries, and error streams.
They establish that these code paths preserve the supplied synthetic rows; they
do not establish what the Windows 11 native provider originally returned. Complete
inventory enables valid DHCP comparison. Removing one inventory row leaves all
14 DHCP records visible and the unmatched record explicitly unassessed. No DHCP
records have been suppressed to conceal the discrepancy. There is no demonstrated
collector inventory-loss defect to fix yet.

**Statistics cause unresolved.** Each latest observation batch has successful
query execution but ProviderRowsAbsent/RowCount=0; targeted snapshot calls retain
CmdletizationQuery_NotFound_Name/ObjectNotFound. There are no rows to match and
no rates. The actual batch invocation is `Get-NetAdapterStatistics -Name '*'
-IncludeHidden -ErrorAction Stop`. The asterisk is deliberately unescaped and
selects the whole batch; literal aliases are escaped only for detail calls.
No error stream is discarded. Tests now exercise empty success, thrown failure,
native-style nonterminating error promotion, present-unmatched rows and a match.
Both batch and targeted nonterminating errors become query failures rather than
successful empty results. Existing bounded batching and counter coverage remain.

Near-contemporaneous Windows 11 comparisons of wildcard, omitted-Name and raw
CIM statistics queries are still missing. The follow-up below supplies them.
Raw CIM uses the installed CDXML class `MSFT_NetAdapterStatisticsSettingData`;
different results would distinguish a query-layer discrepancy for further review,
not prove a driver failure. Raw CIM and cmdlet scopes may differ. No speculative
fallback counters, zero counters or VirtualBox diagnosis were introduced.

**Power behavior unresolved; attribution preserved.** All eight latest literal
queries retain `Windows System Error 31,Get-NetAdapterPowerManagement` and
QueryScope=LiteralAdapterName. Their CIM NativeErrorCode is **1**, separately
from **31** in the Windows error identifier/message. `NativeErrorCode` continues
to mean the exception's exposed field, with ExceptionType identifying its source;
it is not a parsed Windows error number. Messages, identifiers, category, HResult,
requested identity and scope are preserved. No conversion to unsupported,
access-denied or eight hardware faults is justified. No global power fallback,
elevation requirement or network/service change was added.

**Confirmed portability weakness, Windows 11 exception mechanism not isolated.**
Both affected tests built output beneath a potentially long checkout, then added
a descriptive test directory/full GUID, a computer/run directory/full GUID and
an atomic filename containing another full GUID. Production output shares the
run-directory and atomic-name overhead and can encounter the same limits.
The unchanged Windows 11 suites passing after relocation strongly supports path
sensitivity, but DirectoryNotFoundException alone is not proof of MAX_PATH.

ObservationRun and DhcpOrchestration now use unique short temporary working roots
under `%TEMP%/output/tests/<full GUID>`, keeping source loading independent of
artifact placement. Test-LongCheckout copies only source/tests into a synthetic
171-character checkout with spaces and runs both suites without skipping writes.
Separate Test-EntryLoading coverage still loads actual entries and dot-sources
from another working directory and a path with spaces.

Atomic temporary files now use a full GUID basename in the destination directory,
rather than append the GUID to the report name. Exclusive creation, same-volume
atomic replacement, flush, recovery backups, retry behavior and parent-only
persistence remain. Actual PathTooLongException gets a shorter-path explanation
and retains the native InnerException. DirectoryNotFoundException gets a cautious
long-path hint only when the parent is observed present and a persistence path is
at least 260 characters; ordinary missing short directories retain their error.
No blanket length rejection, machine setting, policy change or non-atomic fallback
was introduced. Long directory creation can also fail before persistence starts;
a shorter checkout remains appropriate for production on affected runtimes.

Windows 10 accepted the old 261-character temporary filename, so the Windows 11
failure was not reproduced here. A genuinely unsupported filename exercised the
specific path error, and the new first atomic publication succeeded in the long
directory. Replacement then failed with sandbox File.Replace access denial.
That is an access-control restriction, not evidence of a path-length cause.

Collector patch version is **0.5.4**. Root schema **9**, context **3**, DHCP
observation comparison **3**, and provider/Wi-Fi/timing contracts **1** remain
unchanged. Only persistence mechanics/diagnostics and tests change behavior;
collector inventory/statistics/power selection semantics remain unchanged.

## Validation and remaining Windows 11 commands

See [the exact Windows 10 commands and results](VALIDATION.md#windows-11-follow-up-2026-09-25-collector-054).
Twenty suites passed here; real replacement suites and both passive entry runs
remain blocked by File.Replace denial. Supplied Windows 11 results are separately
recorded there: ten suites, 208 assertions, all exit 0; ObservationRun and
DhcpOrchestration passed after moving to the shorter checkout. Those results
predate these edits and include synthetic providers, not universal live validation.

Only these targeted follow-ups are needed on Windows 11, without elevation or
execution-policy overrides:

```powershell
# From the original long checkout: tests use short artifact roots.
powershell.exe -NoProfile -File .\tests\Test-ObservationRun.ps1
powershell.exe -NoProfile -File .\tests\Test-DhcpOrchestration.ps1
powershell.exe -NoProfile -File .\tests\Test-PathPortability.ps1
powershell.exe -NoProfile -File .\tests\Test-InventoryBoundaries.ps1

# From a short checkout. Substitute one exact observed miniport alias.
powershell.exe -NoProfile -File .\tests\Inspect-Windows11Providers.ps1 -AdapterName 'Local Area Connection* N'
```

The first two distinguish source checkout length from persistence location and
verify real orchestration writes. PathPortability checks missing-directory versus
unsupported-path errors, first publication, replacement, backups and temporary
cleanup; it reports whether the old 261-character temporary name fails locally.
InventoryBoundaries verifies worker preservation and DHCP/error behavior on that
PowerShell runtime using synthetic providers.

The inspector runs each query in its own ten-second worker, serializes explicit
inputs, checkpoints only in the parent and leaves private evidence under output/.
It records generated cmdlet definitions, default/hidden/raw-CIM adapter inventories,
wildcard/omitted-Name/raw-CIM statistics, and the collector inventory in the same
session. Only if the supplied literal alias uniquely matches does it query scoped
statistics and power. It never globally enumerates power. Compare stable GUIDs and
raw rows, not array positions; sequential queries still permit state changes.
This distinguishes a persistent native/collector discrepancy from the current
non-contemporaneous evidence, and documents Windows 11 parameter semantics and
error provenance. No active probes, captures or configuration changes occur.
The inspector is parser-validated here; Windows 11 live provider results remain
pending. Timing and full 120-second observation need no repeat just for these edits.

Private evidence remains ignored/untracked; existing reports are untouched.
The investigation initially left changes uncommitted and unpushed. The user then
explicitly requested review, commit and push of this follow-up. Review added an
immediate inventory checkpoint to the bounded inspector before targeted queries.

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
