# PowerShell CommandHighlighter

Real-time command existence highlighting for **Windows PowerShell 5.1**, inspired by `zsh-syntax-highlighting`.

| Input | Command color |
| --- | --- |
| `Get-Date` | Green (`#4CAF50`) |
| `Get-Datett` | Red (`#FF6688`) |
| `ls nonexistent` | Green for `ls`; the argument is not validated |
| `git status; python --version` | Each command is checked independently |

Colors update while editing, before pressing Enter. Aliases, functions, discoverable module commands, external programs, and explicit script or executable paths are resolved using the current PowerShell session.

**Implementation:** this project builds a small **C# patch to PSReadLine 2.4.5**. It is a separately installed PSReadLine fork, not a plugin using a public token-coloring API. It is an independent project and is not an official Microsoft release.

Project version: **0.1.0 (experimental)**. The patched module uses **2.4.5.1** to distinguish it from its upstream base.

## Upstream provenance

```text
Upstream:     PowerShell/PSReadLine
Base version: v2.4.5
Base commit:  98d5610f7210924b79f553d982e10a9bd64dd52f
License:      BSD-2-Clause
```

The retained build sources come from [this exact upstream commit](https://github.com/PowerShell/PSReadLine/tree/98d5610f7210924b79f553d982e10a9bd64dd52f). Git may normalize line endings according to `.gitattributes`; the upstream code and copyright notices are retained. Project modifications are applied only in build staging. See [vendor/UPSTREAM.md](vendor/UPSTREAM.md), [machine-readable provenance](vendor/PSReadLine.provenance.json), and [the review patch](docs/PSReadLine-v2.4.5.patch).

## Features

- Checks only statically identifiable command names using PowerShell's AST and command discovery.
- Handles pipelines, multiple statements, nested script blocks, and quoted commands after `&`.
- Leaves arguments, comments, ordinary strings, variables, and unresolved dynamic expressions to normal syntax coloring.
- Keeps PSReadLine's renderer, selection, editing, completion, history, and prediction paths.
- Preserves unaccepted inline predictions as prediction text.
- Uses a bounded, short-lived cache without launching a process for each keystroke.
- Installs to a separate current-user version directory without editing your profile or replacing existing module files.

A green command is discoverable, not guaranteed to execute successfully. Parameters, execution policy, program installation placeholders, and command results are outside the feature's scope. Discovery can auto-import modules and run their initialization code; the input command itself is never invoked for highlighting.

## Requirements

| Purpose | Requirements |
| --- | --- |
| Run | Windows PowerShell 5.1, its .NET Framework runtime, and a VT-capable terminal such as Windows Terminal |
| Build | .NET SDK 8.x and network access for the initial NuGet restore |
| Build from WSL/Linux | The same SDK plus Python 3 |
| Run integration tests | Windows with ConPTY support; the tested desktop platform is Windows 11 |

PowerShell 7 deployment is not validated. The installer intentionally targets Windows PowerShell Desktop. Oh My Posh is optional and continues to use your existing configuration.

## Build and try without installing

Clone or download this repository to a **local Windows directory** and open Windows PowerShell in its root. Generated DLLs and release archives are not checked into this source repository.

```powershell
dotnet --version
.\build.ps1
.\demo.ps1
```

The demo starts a nested PowerShell session with the patched module discoverable **before startup**, then loads your normal profile. Type `Get-Date`, append `tt`, and press Backspace twice to observe green, red, and green. Run `exit` to return to the original session.

Use `.\demo.ps1 -NoUserProfile` for a clean session. The demo does not change persistent environment variables or profile files. Commands you execute in a normal demo session follow your own history settings.

For a WSL/Linux build:

```sh
python3 tools/build_wsl.py /path/to/dotnet
```

Only if a minimal build environment lacks ICU, set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` for that build process. This is not needed in a normal Windows setup.

The build copies the pinned upstream source to `.build/upstream`, applies guarded patches, and publishes to `artifacts/PSReadLine/2.4.5.1/`. Patch preparation fails if an expected upstream anchor changes. Building does not install anything.

## Install

After building:

```powershell
.\install.ps1 -WhatIf
.\install.ps1
```

The default destination is calculated from the current user's Documents folder:

```text
<Documents>\WindowsPowerShell\Modules\PSReadLine\2.4.5.1\
```

Open a **new Windows PowerShell process**. The new user module version is intended to be selected ahead of upstream 2.4.5. Existing modules, your profile, Oh My Posh configuration, terminal settings, and execution policy are left unchanged. No administrator privileges are needed.

Check the loaded module:

```powershell
Get-Module PSReadLine | Select-Object Version
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled
```

The version should be `2.4.5.1` and highlighting should be enabled. To diagnose loading locally, inspect `[Microsoft.PowerShell.PSConsoleReadLine].Assembly.Location`; redact personal paths before sharing that output.

Interactive PowerShell imports PSReadLine before running profiles. Importing a different build late in a profile cannot reliably replace an already loaded assembly. No new profile initialization is required. Existing `Import-Module PSReadLine -MinimumVersion 2.2.0` configuration can reuse the patched module; configurations pinned to another exact version need review.

The installer refuses to overwrite an unrelated directory and stops when an equal or newer unowned PSReadLine version is available. If your execution policy rejects scripts from a network share, use a reviewed local checkout; these scripts do not change execution policy.

## Disable and uninstall

Disable existence coloring in the current session:

```powershell
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $false
```

Re-enable it and clear cached results:

```powershell
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $true
[Microsoft.PowerShell.PSConsoleReadLine]::ClearCommandHighlighterCache()
```

The next normal edit or redraw uses the updated setting. To uninstall, run a clean process from the repository root so the module DLL is not locked by the uninstaller:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\uninstall.ps1
```

Only the version directory carrying this project's ownership record is removed. A new shell can select the original PSReadLine again. No profile restoration is required. Pass the same `-InstallRoot` to installation and uninstallation if using a custom destination; custom destinations must already be discoverable at shell startup.

## Tests and performance

Run each test in a clean process after building:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Highlighter.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Installation.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Interactive.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Source.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Distribution.ps1
```

The source test prepares a fresh staging tree; it does not remove published artifacts. Optional profile and installed-module integration checks are described in [validation notes](docs/validation.md).

The development validation passed **131 semantic/render checks** and **16 real ConPTY interaction checks** per tested configuration. ConPTY tests exercise actual input, deletion, completion, undo/redo, history search, multiline input, and accepting a gray inline prediction. They do not replace visual Windows Terminal testing.

A recorded benchmark measured parser plus highlighter P95 at **20.708 ms for cold typing**. There is no universal 20 ms guarantee, especially for missing commands or slow search paths. See [the measurement scope and results](docs/validation.md#performance) and [sanitized benchmark data](docs/benchmarks/windows-powershell-5.1.json).

Run your own benchmark without collecting account paths or environment dumps:

```powershell
New-Item test-results -ItemType Directory -Force | Out-Null
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Measure-Highlighter.ps1 -OutputPath .\test-results\benchmark.json
```

A [Windows CI workflow](.github/workflows/ci.yml) builds and runs the automated checks. Its hosted execution still needs to be confirmed after publishing; no passing CI status is implied by this README.

## Architecture and maintenance

The C# implementation lives in [src/CommandExistenceHighlighter.cs](src/CommandExistenceHighlighter.cs). Three guarded integration points connect it to PSReadLine's input parsing, token color selection, and per-prompt initialization. Module and assembly metadata identify the local build. Review the [upstream patch](docs/PSReadLine-v2.4.5.patch) and [technical rationale](docs/feasibility.md).

Discovery uses `EngineIntrinsics.InvokeCommand.GetCommand(name, CommandTypes.All)` in the active session. Cache entries expire after 250 ms, are bounded to 512 names, and are cleared for each new ReadLine call and relevant environment/location changes. Dynamic command targets are never evaluated.

This fork needs review when rebasing onto a newer PSReadLine. A newer upstream module can take precedence and disable the custom coloring. Do not increase the local version merely to outrank an unreviewed release. This patched `PSReadLine` package is not published to PowerShell Gallery under Microsoft's package identity.

## Repository layout

```text
src/            Additional C# implementation
tests/          PowerShell checks and the ConPTY harness
tools/          WSL build helper and public-source checks
docs/           Design, validation, patch, and sanitized benchmarks
vendor/         Pinned PSReadLine build sources and upstream license
third-party/    Pager license and original package metadata
.github/        Windows CI workflow and issue template
```

## Contributing and licensing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development, review, and privacy guidance. There is already a related [upstream feature request](https://github.com/PowerShell/PSReadLine/issues/3439); discuss architecture there before opening a duplicate proposal.

New project code is MIT-licensed. Vendored PSReadLine remains under its original BSD-2-Clause license and retained copyright notices. See [LICENSE](LICENSE), [the upstream license](vendor/PSReadLine/License.txt), and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Source distributions must retain the vendored notices and license files. Binary distributions should include the complete generated module directory: `License.txt` (PSReadLine), `CommandHighlighter-LICENSE.txt` (project additions), `THIRD-PARTY-NOTICES.md`, `UPSTREAM.json`, and `third-party/` accompany the DLLs. Do not distribute only a DLL. See the [distribution inventory and checks](docs/distribution.md).
