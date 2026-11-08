# Contributing

This project maintains a small PSReadLine fork for Windows PowerShell 5.1. Keep changes narrowly scoped and distinguish verified behavior from assumptions.

## Development

1. Build from the repository root with `.\build.ps1` using .NET SDK 8.x.
2. Run the semantic, installation, interactive, and source checks listed in the README in separate `powershell.exe -NoProfile -NonInteractive` processes.
3. Use `.\demo.ps1` for manual testing; install only when validating the installed startup path.
4. Run `python tools/check_public_source.py` before committing. The checker requires Git and Python 3 and scans tracked plus non-ignored untracked files.

After building, also run `tests/Test-Distribution.ps1` in a clean Windows
PowerShell process. It checks the source notice inventory and the complete
binary payload, including full licenses and exact upstream provenance. See
[the distribution guide](docs/distribution.md).

The default installation test uses a temporary directory. Never point an automated uninstall test at another person's module directory or replace existing system modules for a test.

## Source and licensing

`vendor/PSReadLine/` contains an unmodified build-source subset pinned in `vendor/UPSTREAM.md`. Make project changes in `src/` and the guarded build patches. If a rebase is required, review the upstream renderer and discovery behavior, update provenance and the review patch, and rerun the relevant tests.

Keep upstream notices and licenses intact. New project files use the root MIT license; vendored files retain their original license. Do not publish the fork as the official `PSReadLine` package.

## Reporting issues

Write reports and code comments in English. Include a minimal input example, expected and actual colors, PowerShell and module versions, and the editing operation involved. Avoid posting your full profile or environment.

Do not include account names, local workspace paths, raw terminal transcripts, history files, environment snapshots, credentials, or private repository names. If a small diagnostic excerpt is needed, review and redact it first. Unicode test data is welcome; use explicit escapes when practical to keep comments and documentation in English.

The source checker catches common mistakes and generated/private file types. It is a heuristic, not a substitute for reviewing a diff. Do not commit generated DLLs, package caches, test output, or local release archives.

## Pull requests

Explain the behavior changed and the checks actually run. Include a cold-discovery benchmark when changing lookup or caching. Mention module initialization side effects and current-session visibility when proposing asynchronous discovery.

For an upstream contribution, review the existing [command coloring request](https://github.com/PowerShell/PSReadLine/issues/3439) and [PSReadLine contribution guide](https://github.com/PowerShell/PSReadLine/blob/master/.github/CONTRIBUTING.md). This fork's implementation is a discussion prototype, not a claim of upstream acceptance.
