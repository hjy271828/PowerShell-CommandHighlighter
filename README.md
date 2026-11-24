# PowerShell CommandHighlighter

Real-time command highlighting for **Windows PowerShell 5.1**, inspired by `zsh-syntax-highlighting`. As you type, valid commands turn green and unknown ones turn red, before you press Enter.

| Input | Result |
| --- | --- |
| `Get-Date` | Green (`#4CAF50`) |
| `Get-Datett` | Red (`#FF6688`) |
| `ls nonexistent` | `ls` is green; arguments keep normal coloring |
| `git status; python --version` | Each command is checked on its own |

## Quick start

1. Download `PowerShell-CommandHighlighter-v0.1.1-windows-powershell5.1.zip` from the [latest release](https://github.com/hjy271828/PowerShell-CommandHighlighter/releases/tag/v0.1.1) and extract it to a local folder.
2. Open Windows PowerShell in that folder and run:

   ```powershell
   .\install.ps1
   ```

3. Open a new PowerShell window and type `Get-Date`, then `Get-Datett`.

That's it. No admin rights, profile edits, or extra configuration needed. Your existing profile, Oh My Posh theme, and terminal settings keep working as before.

If Windows blocks the downloaded scripts, run `Get-ChildItem -Recurse -File | Unblock-File` in the extracted folder first. The ZIP's own README has more details.

### Turn it off or uninstall

```powershell
# Toggle for the current session
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $false

# Uninstall (close other PowerShell windows first)
powershell.exe -NoProfile -File .\uninstall.ps1
```

After uninstalling, new shells go back to the stock PSReadLine.

## Features

- Recognizes cmdlets, aliases, functions, module commands, external programs, and script/executable paths in your current session.
- Works across pipelines, multiple statements, nested script blocks, and quoted commands after `&`.
- Arguments, strings, comments, and variables keep PSReadLine's normal colors.
- Completion, history, selection, undo/redo, and inline predictions all work as usual.
- Fast: lookups are cached briefly, and nothing is executed while you type.

Green means the command can be found, not that it will succeed.

## Compatibility

| | |
| --- | --- |
| Shell | Windows PowerShell 5.1 (PowerShell 7 not yet tested) |
| Terminal | Any VT-capable terminal, e.g. Windows Terminal |
| Tested on | Windows 11 |
| Based on | PSReadLine 2.4.5 (installed as module version `2.4.5.2`) |

## How it works

This project is a small C# patch on top of [PSReadLine](https://github.com/PowerShell/PSReadLine) 2.4.5, installed as a separate module version that PowerShell picks up at startup. It is an independent project, not an official Microsoft release.

- The highlighter lives in [src/CommandExistenceHighlighter.cs](src/CommandExistenceHighlighter.cs) and hooks into PSReadLine at three points: input parsing, token coloring, and per-prompt setup.
- Command names are found statically from the PowerShell AST and resolved with `InvokeCommand.GetCommand(name, CommandTypes.All)`. Dynamic expressions are never evaluated.
- Results are cached for 250 ms (up to 512 names) and the cache resets on each new prompt or when location, aliases, functions, or modules change.

Upstream base:

```text
Upstream:     PowerShell/PSReadLine v2.4.5
Base commit:  98d5610f7210924b79f553d982e10a9bd64dd52f
License:      BSD-2-Clause
```

See the [upstream patch](docs/PSReadLine-v2.4.5.patch), [design notes](docs/feasibility.md), [vendor/UPSTREAM.md](vendor/UPSTREAM.md), and [validation & benchmarks](docs/validation.md).

## Build from source

Requires the .NET SDK 8.x. From the repository root in Windows PowerShell:

```powershell
.\tools\build.ps1
.\examples\demo.ps1     # try it in a nested session without installing
.\install.ps1           # or install it
```

On WSL/Linux: `python3 tools/build_wsl.py /path/to/dotnet`.

Tests, packaging, and release steps are described in [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/releasing.md](docs/releasing.md).

## License

Project code is MIT-licensed. Vendored PSReadLine stays under its original BSD-2-Clause license. See [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
