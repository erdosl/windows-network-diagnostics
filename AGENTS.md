# Project requirements

- Target Windows 10/11 and Windows PowerShell 5.1. Validate with powershell.exe,
  not only pwsh. Use no external runtime dependencies.
- Collect read-only snapshots. Active connectivity probes require explicit
  `-IncludeConnectivityTests`; gateway ICMP additionally requires `-IncludeGatewayPing`.
  Never change network configuration, reset
  adapters, renew leases, change execution policy, or collect credentials.
- Never export Wi-Fi keys. No Eero or UniFi management integration.
- Isolate checks so a failed check does not stop the remaining collection.
  Explicitly record unavailable checks, permission failures, and timeouts.
- Run checks in bounded Windows PowerShell 5.1 workers with explicit serialized
  inputs. Kill the worker and its descendants on timeout/interruption; only the
  parent may write reports. Do not assume caller-scope variables exist in workers.
- Create an incomplete schema-versioned checkpoint before collection. Save completed
  checks by atomic replacement; retain recovery backups and distinguish incomplete
  from complete collections. Preserve computer/run identity and offset timestamps.
- Keep generated diagnostics and local output out of Git. Treat collected
  addresses, MACs, SSIDs, machine names, and event contents as sensitive.
- Separate observations from diagnostic hypotheses. APIPA and simultaneous
  Ethernet/Wi-Fi connections are flags, not proven root causes.
- Distinguish route predictions from observed socket endpoints, and IPv4 from
  IPv6. A ping or DNS failure alone is not a root-cause diagnosis.
- Correlate interfaces within each snapshot by index, retaining multiple addresses
  and routes and missing-source statuses. Preserve raw check evidence below summaries.
- Keep separate network, NIC, and power event budgets, retain event XML, and record
  unsupported providers. Discover NIC service providers without vendor assumptions.
- Snapshot scope: Windows version/time zone, adapters and NIC drivers,
  per-interface addressing/DHCP/gateways/DNS, routes/metrics/neighbours,
  key-free Wi-Fi details, and bounded recent DHCP/TCP-IP/link events.
- Produce JSON evidence and safely HTML-encoded summaries under output/.
- Test address classification, reporting, worker cleanup, incomplete recovery,
  orchestration, event bounds/XML, and optional probes with synthetic data.
- Run actual `.ps1` files and dot-sourcing in powershell.exe when policy permits,
  including another working directory and paths with spaces. Never bypass execution
  restrictions or equate inline execution with end-to-end validation. Document the
  actual Windows version, privileges, commands, test results, and unverified coverage.
- Defer monitoring, subnet scanning, Nmap, vendor lookup, and packet capture.
- Do not commit or push unless explicitly requested by the user.

- Preserve the cleaned noreply-email Git history; never reintroduce original commits.
- Display collection status separately from probe outcome. Worker timeouts leave
  network outcome unknown; ordinary probe failures/timeouts can be collected successfully.
- Use one elapsed-time budget across TCP/TLS/HTTP, plus a separate bounded worker
  overhead allowance. Preserve completed stage evidence on cooperative timeouts.

- Retain full DNS inventory and configured associations. Skip only the three exact
  legacy DNS discovery addresses by default; explicit legacy opt-in also requires
  connectivity opt-in. Never infer the query interface from configured associations.
- Classify DNS errors from reliable numeric exception codes, not localized text;
  retain original errors and separate DNS/probe timeouts from worker termination.
- Put new synthetic orchestration snapshots and recovery fixtures under output/tests/.
  Do not alter or delete existing user diagnostic reports.

- Logical maps derive only from snapshot evidence, with per-node/relationship
  provenance, intervals, evidence type and plain-language limitations. Never invent
  physical infrastructure or merge remote endpoints with gateway/MAC identities.
- Retain neighbour states/raw values and interface/scope context. Filter only
  endpoint-observation counts; do not describe them as verified physical devices.
- Collect adapter statistics/power settings in independent bounded per-adapter
  checks. Counters are cumulative samples, not rates/current-fault diagnoses.

- Adapter-provider missing-object classification must be scoped to structured
  provider errors after correct literal/hidden targeting. Distinguish generated
  no-match records (no native exception) from thrown provider errors; preserve the latter
  and identity; unavailable does not prove hardware fault or lack of support.
- APIPA findings retain every address and interface context. Prioritize active
  physical links, preserve missing sources/raw enums, and keep DHCP possibilities
  separate from observations. Never infer host-only purpose from adapter names.

- A selected DHCP server and successful client probes do not assess competing
  DHCP servers on the LAN. Label this coverage gap explicitly.
- Optional baseline/expectation inputs use bounded workers; input errors must not
  discard the ordinary snapshot. Compare stable GUIDs, expose ambiguity, and never
  infer continuity between snapshots or match solely on MAC, alias or index.
- Expectations are supplied policy, not a rogue-server detector. Missing or
  disconnected evidence is not a mismatch. Historical event correlation uses
  explicit structured identifiers, preserves provenance, and does not establish cause.

- Derived missing scalars must be real nulls (not AutomationNull); empty address
  collections contain no null elements. Preserve raw input and availability metadata.
- Store baseline source records once, limited to consumed check families. References
  identify snapshot scope/run and resolve within the report; never import prior
  comparisons or nested baseline history. Keep important changes visible and carry
  adapter state into comparison presentation.
