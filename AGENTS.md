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
