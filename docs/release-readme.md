# PowerShell CommandHighlighter - binary release

Experimental v0.1.1 for Windows PowerShell 5.1. This package contains a patched
PSReadLine 2.4.5 build with real-time command existence coloring. Its local
module version is 2.4.5.2. It is not an official Microsoft release.

## Requirements

- Windows PowerShell 5.1 and its .NET Framework runtime.
- A VT-capable terminal, such as Windows Terminal.

The desktop validation platform was Windows 11. PowerShell 7 deployment is
not validated. You do not need the .NET SDK, Git, or Python to use this package.

## Install

1. Verify the ZIP against `SHA256SUMS.txt` from the same release.
2. Extract the complete ZIP into a local folder.
3. Open Windows PowerShell 5.1 in that extracted folder.
4. Run:

```powershell
.\install.ps1 -WhatIf
.\install.ps1
```

Open a new Windows PowerShell tab. Type `Get-Date`, append `tt`, and delete
those characters to observe green, red, and green before pressing Enter.

The installer adds a separate user module directory. It does not edit your
profile, existing module files, Oh My Posh theme, or execution policy. It
refuses to overwrite an unrelated directory or silently outrank a newer
unowned PSReadLine release. Version 2.4.5.1 from v0.1.0 is retained for rollback. If the installation already exists but differs,
review/uninstall that installation before installing this build.

If a downloaded-file restriction blocks scripts you have reviewed and trust,
unblock only the extracted package before retrying:

```powershell
Get-ChildItem -LiteralPath . -Recurse -File | Unblock-File
```

This removes the downloaded-file mark from these files; it does not change
execution policy. Do not run it from an unrelated parent directory.

## Try without installing

```powershell
.\demo.ps1
```

This launches a nested shell using the included build and your normal profile.
Use `exit` to return to the original shell. The normal profile's history saving
settings still apply to commands you execute in the demo.

## Check or disable

```powershell
Get-Module PSReadLine | Select-Object Version
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $false
```

Version 2.4.5.2 should be loaded. Setting Enabled to false restores normal
syntax-category coloring on the next edit/redraw. Set it to true to re-enable.

## Uninstall

Close other shells that use this build, then run from this extracted folder
in a clean shell or from Command Prompt:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\uninstall.ps1
```

Open a new shell to select the original PSReadLine again. Custom installations
need the same `-InstallRoot` for installation and removal.
If a DLL is still in use, removal stops before deleting module files. Close the
remaining sessions and retry; the ownership record is retained for retries.

## Boundaries

Only statically identifiable command names are checked. A green command can
still fail at execution time. Dynamic invocation targets retain default
coloring. Recognized pending environment changes also leave affected names
neutral while unrelated commands remain highlighted. Discovery may auto-import modules and run their initialization code;
the input command is not invoked for highlighting. Cold lookups can exceed
20 ms. See `RELEASE-NOTES.md` for validation scope and known limitations.

Keep the entire `artifacts/PSReadLine/2.4.5.2/` directory together. It includes
the original PSReadLine license, project license, Pager license, third-party
notices, and `UPSTREAM.json`. The root `LICENSE` covers project additions;
it does not relicense the vendored PSReadLine components.
