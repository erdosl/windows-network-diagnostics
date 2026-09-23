# Project requirements

- Target Windows 10/11 and Windows PowerShell 5.1. Validate with powershell.exe,
  not only pwsh. Use no external runtime dependencies.
- Collect read-only snapshots. Never change network configuration, reset
  adapters, renew leases, change execution policy, or collect credentials.
- Never export Wi-Fi keys. No Eero or UniFi management integration.
- Isolate checks so a failed check does not stop the remaining collection.
  Explicitly record unavailable checks and permission failures.
- Keep generated diagnostics and local output out of Git. Treat collected
  addresses, MACs, SSIDs, machine names, and event contents as sensitive.
- Separate observations from diagnostic hypotheses. APIPA and simultaneous
  Ethernet/Wi-Fi connections are flags, not proven root causes.
- Snapshot scope: Windows version/time zone, adapters and NIC drivers,
  per-interface addressing/DHCP/gateways/DNS, routes/metrics/neighbours,
  key-free Wi-Fi details, and bounded recent DHCP/TCP-IP/link events.
- Produce JSON evidence and safely HTML-encoded summaries under output/.
- Test address classification and report generation with synthetic data.
- Defer monitoring, subnet scanning, Nmap, vendor lookup, and packet capture.
- Do not commit or push unless explicitly requested by the user.
