# Validation notes

## v0.1.1 hardening validation

Validation on 2026-11-09 used Windows PowerShell 5.1.26100.9711, Windows 11,
and native .NET SDK 8.0.427. The baseline was rebuilt from commit
`2d7b91167f891c86b9c02b973da8876adadd91eb`; it passed the original 131 semantic/
render assertions, installation regression and 16 ConPTY checks before changes.
The new fork uses module version 2.4.5.2; upstream remains pinned to v2.4.5.

The [v0.1.1 pre-release](https://github.com/hjy271828/PowerShell-CommandHighlighter/releases/tag/v0.1.1)
was published on **2026-11-09**, tagging merge commit
`e7e7ccafa2dc96faf838abae039e9aa5560a950b`.
The [hosted Build and test run](https://github.com/hjy271828/PowerShell-CommandHighlighter/actions/runs/42553575211)
passed for that exact commit on the `windows-2022` runner, including build,
patch checks, command analysis, installation, ConPTY editing, packaging and
extracted-ZIP validation. The timing measurements below remain local results;
the experimental upstream workflow is separate from this release CI run.

The v0.1.1 review covers:

| Check | Result |
| --- | --- |
| Existing semantic/render tests | All 131 assertions retained and passed. |
| Dynamic/discovery/cache tests | All 97 assertions passed, including pending definitions, scopes, module discovery/removal, autoload settings, explicit scripts and cache invalidation. |
| Context patch failures | 16 native PowerShell assertions passed; all four patched files matched Python preparation byte for byte. |
| Offline helper tests | Eight Python unittest cases passed, including late mismatches, repeated injection, metadata drift, throttling, retry bounds and unsafe archives. |
| Publication failures | Compiler failure and missing output preserved the complete preceding artifacts; experimental package/install attempts were rejected. |
| Installation regression | Clean/repeat install, modified build, locked files, unowned content, traversal, junctions, interrupted removal, copy failure, version conflict, rollback and literal bracket paths passed. |
| Preservation | Existing profile/module hashes and execution policies were unchanged. Tests used temporary module roots. |
| Real interactive editor | 21 ConPTY assertions passed, retaining original editing/prediction coverage and adding pending alias/function/PATH cases. |
| Extracted ZIP | Checksum, exact 25-file inventory, licenses, fresh loading, 21 installed-module ConPTY checks and uninstall passed. |
| Workflow validation | Both workflows passed actionlint 1.7.12; the release commit's hosted Build and test run also passed, as linked above. |

Only sanitized timing/version data is committed. Private paths, profile data,
raw terminal output and local installation state are excluded. Windows GUI,
clipboard, all Vi modes, PowerShell 7 and the full upstream xUnit suite remain
outside this validation. See [hardening.md](hardening.md) for safeguards and
static-analysis/discovery limits.

### Performance comparison

The original single-version benchmark was retained. Three alternating separate-
process runs per version showed substantial machine/discovery variance:
cold-typing P95 varied from 23.465 to 55.615 ms in the rebuilt v0.1.0 baseline
and 51.594 to 55.601 ms in the candidate. These do not establish a universal
latency bound or a reliable regression percentage.

A new `tests/Compare-Highlighter.ps1` loads both distinct assembly versions in
one Windows PowerShell process and alternates which version is measured first.
Each scenario warms both instances for eight iterations before taking 160
samples each. Both versions use the same parser, session and OS discovery state.
The scope remains parser plus analysis, excluding editor rendering/prediction/
terminal I/O. Cache TTL/capacity remain **250 ms / 512 names**.

| Scenario | v0.1.0 median / P95 (ms) | v0.1.1 median / P95 (ms) |
| --- | ---: | ---: |
| Cached command | 0.014 / 0.024 | 0.016 / 0.024 |
| Cold valid | 0.027 / 0.406 | 0.032 / 0.384 |
| Cold missing | 9.898 / 19.909 | 9.884 / 20.036 |
| Cold typing | 17.012 / 19.405 | 16.697 / 19.444 |
| Cached typing | 0.008 / 0.009 | 0.008 / 0.010 |
| Approximately 36 KB line | 0.951 / 1.714 | 0.968 / 1.313 |
| 100 statements | 0.120 / 0.274 | 0.133 / 0.282 |

No unacceptable key-path regression was observed in this environment: paired
cold-typing P95 increased 0.039 ms, long-line P95 decreased 0.401 ms,
and 100-statement P95 increased 0.008 ms. These are observations, not a guarantee.
Candidate cold-missing maximum was 34.937 ms and separate-process runs were much
noisier. The original v0.1.0 recorded cold-typing P95 was 20.708 ms and long-line
P95 was 1.725 ms; hardware/session variation prevents treating that older run
as a controlled before/after comparison. The sanitized [comparison data](benchmarks/v0.1.1-comparison.json)
retains all separate-process runs and the earlier same-process measurement.

To repeat the paired comparison, keep the preceding release DLL in a separate
local directory and run:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Compare-Highlighter.ps1 -BaselineAssembly .\previous\Microsoft.PowerShell.PSReadLine.dll -OutputPath .\test-results\comparison.json
```

### Live upstream probe observations

On 2026-11-09 the latest semantic tag was still v2.4.5 at the pinned SHA. Its
full upstream snapshot passed preparation, native build, semantic/dynamic tests
and 21 ConPTY assertions in the experimental sandbox.

Master at `a2d143f78904f8a954f8d4b055e55ceca6939bfc` differed in five retained
files and lacked three baseline files, including `Polyfill/Polyfill.csproj`.
Rendering hooks still matched, but the experimental build failed because that
build project no longer exists. Diagnostics reported the failing phase; master
is not supported and was not released. The missing-input diagnostic was then
made explicit in the build helper. The supported vendor tree was unchanged.

The weekly workflow is available on the default branch after the merge. A probe summary
must be read by its JSON status, not inferred from a green experimental job.
Offline/rate-limit inputs are unavailable; experimental failures never create
Issues or publish DLLs. See [the workflow](../.github/workflows/upstream-compatibility.yml).

## Recorded v0.1.0 development validation

The initial validation used Windows 11, Windows PowerShell **5.1.26100.9711**, and a patched PSReadLine module version **2.4.5.1**. Compilation used .NET SDK **8.0.427** on WSL/Linux, with the resulting DLLs loaded and exercised in Windows PowerShell. These are observations from one development environment, not a support matrix covering every Windows configuration.

Personal account names, machine paths, environment snapshots, profile hashes, and raw terminal transcripts are deliberately excluded from this repository.

| Check | Recorded result |
| --- | --- |
| Full Linux build | Main module and both upstream polyfills compiled and published. |
| Full Windows release build | Portable .NET SDK 8.0.427 compiled and published the module and both polyfills through build.ps1. |
| Windows build preparation | `build.ps1 -PrepareOnly` succeeded; four patched files matched the WSL build preparation byte-for-byte. |
| Semantic and render checks | 131 assertions passed, including the actual patched `GenerateRender`/`GetTokenColor` path. |
| Temporary installation | Install, uninstall, idempotence, `-WhatIf`, ownership protection, and an unchanged profile hash passed. |
| Real interactive editor | 16 ConPTY checks passed with a clean test profile. |
| Existing profile | The same 16 checks passed with an existing Oh My Posh/PSReadLine profile. |
| Installed startup | The same 16 checks passed with default module discovery, without a temporary search-path override or explicit patch import. |
| Original setup | Existing profile, theme, upstream DLL, and execution policy were unchanged during installation validation. |
| Final release ZIP | Checksum, exact file inventory, notices, extraction, temporary installation, fresh-process loading, 16 installed-build ConPTY checks, and removal passed. |
| Release failure cases | A wrong checksum was rejected; extra build files were excluded; different-build reuse and removal of a locked DLL were rejected without overwriting the installation. |
| Binary path privacy | Project-built DLLs passed local account path checks after compiler debug symbols were disabled. |

The initial development session used cross-compilation and Windows build
preparation. Release preparation subsequently completed a full native Windows
SDK build and reran the relevant checks successfully. The repository is now
public, and its [initial hosted CI run](https://github.com/hjy271828/PowerShell-CommandHighlighter/actions/runs/42489661573)
completed successfully for commit `34e6c38b0a1b54ba429a8f0eb2093ab66c3f2ccf`.
That run predates the release ZIP workflow, binary path checks, and installation
hardening prepared afterward. Verify a passing hosted run for the new release
commit before publishing its assets. The bundled subset does not include or
run the upstream xUnit test suite.

After preparing the public source tree, the Linux build, 131 semantic/render checks, 16 clean-profile ConPTY checks, temporary installation/removal checks, and Windows PowerShell script parsing were run again successfully. Fresh `-File` launches also exercised repository-relative artifact discovery. Public-source checks and CI YAML parsing passed locally. The initial commit's hosted run was subsequently verified; the later release-preparation changes require their own passing hosted run.

The distribution review rebuilt the module and checked both a source snapshot
archive and the compiled payload in Windows PowerShell 5.1. Full licenses,
third-party notices, and exact upstream provenance were present and matched
their source copies. A negative check that removed the binary's upstream
license failed as expected. The new distribution check is included in CI;
see [distribution.md](distribution.md) for the file inventory and commands.

Release validation used the ZIP itself, with a temporary module search path
scoped to the test process tree. It left the normal user module installation
unchanged. An explicit inventory check confirmed that extra fixture files in
build output and the source third-party directory did not enter the package.
The source parsing check covered 14 project scripts. See
[releasing.md](releasing.md) for the local package and CI workflow commands.

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
