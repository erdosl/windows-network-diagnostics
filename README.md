# Windows network diagnostics

Repository for Windows network diagnostic source code and documentation.
No diagnostic scripts have been added yet.

## Repository layout

- `src/`: diagnostic source code (create when adding scripts).
- `docs/`: usage and troubleshooting documentation (create as needed).
- `reports/`, `captures/`, and `output/`: local generated data, excluded from Git.

## Keeping diagnostic data private

Write generated reports to `reports/`, packet captures to `captures/`, and other
local output to `output/`. Diagnostic data can contain machine names, network
addresses, traffic contents, and other sensitive information. Do not commit it.

The `.gitignore` file excludes these directories, common capture and trace
formats, logs, archives, credential files, private keys, and local environment
configuration. Keep credentials out of source code and documentation. Any
`.env.example` file must contain placeholders only.

Ignore rules do not detect secrets embedded in source files and do not protect
files that are already tracked. Before committing, inspect both the file list
and the staged contents:

```powershell
git status --short
git diff --cached --stat
git diff --cached
```

Stage source and documentation explicitly. Avoid force-adding ignored files.

## Contributing

Start from the current `main` branch, add source and accompanying documentation,
and commit only reviewed files. Fetch remote changes before pushing and reconcile
any divergence. Push normally; do not force-push or replace remote history.

## License

See [LICENSE](LICENSE).
