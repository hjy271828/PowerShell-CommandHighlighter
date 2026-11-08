# Validation notes

## Recorded development validation

The initial validation used Windows 11, Windows PowerShell **5.1.26100.9711**, and a patched PSReadLine module version **2.4.5.1**. Compilation used .NET SDK **8.0.427** on WSL/Linux, with the resulting DLLs loaded and exercised in Windows PowerShell. These are observations from one development environment, not a support matrix covering every Windows configuration.

Personal account names, machine paths, environment snapshots, profile hashes, and raw terminal transcripts are deliberately excluded from this repository.

| Check | Recorded result |
| --- | --- |
| Full Linux build | Main module and both upstream polyfills compiled and published. |
| Windows build preparation | `build.ps1 -PrepareOnly` succeeded; four patched files matched the WSL build preparation byte-for-byte. |
| Semantic and render checks | 131 assertions passed, including the actual patched `GenerateRender`/`GetTokenColor` path. |
| Temporary installation | Install, uninstall, idempotence, `-WhatIf`, ownership protection, and an unchanged profile hash passed. |
| Real interactive editor | 16 ConPTY checks passed with a clean test profile. |
| Existing profile | The same 16 checks passed with an existing Oh My Posh/PSReadLine profile. |
| Installed startup | The same 16 checks passed with default module discovery, without a temporary search-path override or explicit patch import. |
| Original setup | Existing profile, theme, upstream DLL, and execution policy were unchanged during installation validation. |

A full Windows SDK build was not run during the recorded development session. The CI workflow is configured to perform it after publication; it has not yet run on a hosted runner. The bundled subset does not include or run the upstream xUnit test suite.

After preparing the public source tree, the Linux build, 131 semantic/render checks, 16 clean-profile ConPTY checks, temporary installation/removal checks, and Windows PowerShell script parsing were run again successfully. Fresh `-File` launches also exercised repository-relative artifact discovery. Public-source checks and CI YAML parsing passed locally; hosted CI execution remains unverified.

The distribution review rebuilt the module and checked both a source snapshot
archive and the compiled payload in Windows PowerShell 5.1. Full licenses,
third-party notices, and exact upstream provenance were present and matched
their source copies. A negative check that removed the binary's upstream
license failed as expected. The new distribution check is included in CI;
see [distribution.md](distribution.md) for the file inventory and commands.

## Semantic coverage

The tests cover:

- Cmdlets, aliases, functions, missing command names, and external commands discovered in the test session.
- Arguments excluded from validation, including non-existent path arguments.
- Pipelines, semicolon-separated commands, multiline input, nested script blocks, and command substitutions inside strings.
- Quoted static commands after `&`, ordinary quoted strings, comments, and variables.
- Dynamic invocation targets skipped rather than evaluated.
- Empty input and incomplete operators, quotes, parentheses, or pipelines.
- Relative and absolute Unicode script paths, missing explicit paths, and a newly created test executable.
- A temporary module discovered and auto-imported through PSModulePath, without invoking its exported function.
- PATH invalidation and short-lived positive/negative function discovery entries.
- A temporary reduced PATH that simulates an environment without Git. The tests do not uninstall or reinstall Git.

## Interactive coverage

The ConPTY harness runs a real interactive Windows PowerShell process. It sends input and editing keys, inspects the editor's generated input lines, and confirms that red and green ANSI sequences reach the pseudoconsole. It does not print a colored substitute for the input buffer.

| Operation | Observed behavior |
| --- | --- |
| `Get-Dat` -> `Get-Date` -> `Get-Datet` | Red -> green -> red before Enter. |
| Backspace | Restoring `Get-Date` restores green. |
| Cursor movement and Delete | Removing extra characters updates the command color. |
| Batched text input | Multiple statements and pipeline commands receive independent colors. |
| Tab completion | The completed command receives the expected color. |
| Ctrl+A replacement | Replaced input is recolored. |
| Ctrl+Z / Ctrl+Y | Undo and redo update the color. |
| History / Ctrl+R | Recalled and searched input is recolored. |
| Inline prediction | Unaccepted prediction remains gray. |
| RightArrow / ForwardChar | Accepting the prediction makes it ordinary input. |
| Multiline editing | A command inside an unfinished `if` block is colored. |

The F12 snapshot handler exists only in the test child process. Test sessions disable history saving. Existing user-profile tests are opt-in because profiles may run arbitrary user setup code.

Run additional local checks after building:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Interactive.ps1 -UseUserProfile
# Only after installing the patched module:
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Interactive.ps1 -UseUserProfile -UseInstalledModule
```

Raw transcripts can contain prompt text, account paths, history suggestions, and application output. If needed for local debugging, use an ignored destination such as `test-results/`; review and redact it before sharing. The public-source check rejects accidentally added raw transcripts and environment dumps.

## Performance

Each scenario contains 160 samples, in milliseconds. Timing covers **Parser.ParseInput plus Analyze**, excluding process/module startup, the rest of PSReadLine rendering, prediction lookup, and terminal I/O. Since PSReadLine already parses input, this is not an exact measurement of additional full-frame latency.

| Scenario | Median | P95 | Maximum |
| --- | ---: | ---: | ---: |
| Cached `Get-Date` | 0.012 | 0.021 | 4.672 |
| Existing commands, project cache cleared | 0.033 | 0.416 | 0.593 |
| Missing commands, project cache cleared | 10.500 | 20.483 | 22.194 |
| Typing prefixes, cache cleared each sample | 17.273 | 20.708 | 23.504 |
| Typing prefixes with short-lived caching | 0.007 | 0.010 | 24.858 |
| Approximately 36 KB of arguments | 0.937 | 1.725 | 4.655 |
| 100 `Get-Date` statements | 0.126 | 0.215 | 1.071 |

Cold refers to this project's cache, not cleared operating-system or PowerShell internal caches. The cached sequence's maximum includes rediscovery after expiry. The 20 ms target was not met as a strict bound: missing-command and cold-typing P95 exceeded it slightly. Network paths or module initialization may be substantially slower.

The recorded, sanitized data is in [benchmarks/windows-powershell-5.1.json](benchmarks/windows-powershell-5.1.json). Use `tests/Measure-Highlighter.ps1` to measure another environment; its report contains timings and version information rather than environment dumps.

## Manual checks and unverified areas

ConPTY is not the Windows Terminal GUI. Before a release, check:

1. Prompt appearance, Nerd Font glyphs, and transient prompt behavior in the intended terminal/profile.
2. Live green/red transitions without pressing Enter.
3. System clipboard Ctrl+V, selection followed by Ctrl+V, and terminal paste shortcuts. Automated tests cover batched input without changing the clipboard.
4. Long wrapped lines, Unicode and emoji display, selection, resizing, scrolling, and multiline cursor positioning.
5. Previously executed lines and normal history display.

PowerShell 7 deployment, every Vi editing mode, all terminal geometries, and the full upstream xUnit suite are not verified by these checks. Do not claim those as passing based on the recorded results.
