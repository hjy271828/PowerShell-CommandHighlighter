# Distribution inventory

This project includes separately licensed components. The root MIT license
applies to project additions; it does not replace the upstream PSReadLine
license or the Pager license. Retain the complete license texts and existing
source-file copyright notices in source and binary distributions.

## Source distributions

Keep these files in a source archive or checkout:

| File | Purpose |
| --- | --- |
| `LICENSE` | MIT terms for project additions |
| `THIRD-PARTY-NOTICES.md` | Component attribution and license boundaries |
| `vendor/PSReadLine/License.txt` | Original PSReadLine BSD-2-Clause terms |
| `vendor/UPSTREAM.md` | Source subset and modification description |
| `vendor/PSReadLine.provenance.json` | Repository, exact base tag/commit, license, and fork version |
| `third-party/Pager-LICENSE.txt` | Original Pager MIT license text |
| `third-party/microsoft.powershell.pager.nuspec` | Original dependency package metadata |

Retain the notices inside vendored source files as well. The source subset is
pinned to `v2.4.5`, commit `98d5610f7210924b79f553d982e10a9bd64dd52f`.
Git can normalize line endings; the code and attribution remain unchanged.

## Binary distributions

Both build scripts produce the same module layout:

```text
PSReadLine/2.4.5.1/
  Microsoft.PowerShell.PSReadLine.dll
  Microsoft.PowerShell.Pager.dll
  PSReadLine.psd1
  PSReadLine.psm1
  PSReadLine.format.ps1xml
  netstd/Microsoft.PowerShell.PSReadLine.Polyfiller.dll
  net6plus/Microsoft.PowerShell.PSReadLine.Polyfiller.dll
  License.txt
  CommandHighlighter-LICENSE.txt
  THIRD-PARTY-NOTICES.md
  UPSTREAM.json
  third-party/
    Pager-LICENSE.txt
    microsoft.powershell.pager.nuspec
```

Distribute the complete directory, including notices, rather than an isolated
DLL. `install.ps1` copies this complete directory to the user module location.
The installed module's additional ownership record is local installation
metadata and is not needed in a release archive.

The user-facing release ZIP wraps this complete module under
`artifacts/PSReadLine/2.4.5.1/` and also includes `install.ps1`, `uninstall.ps1`,
`demo.ps1`, `release.json`, a standalone README, release notes, the changelog,
and top-level project/third-party notices. Run `package.ps1` after building.
It copies an explicit inventory, rather than every file found in artifacts.
The versioned ZIP and its `SHA256SUMS.txt` are the files attached to a release.

`THIRD-PARTY-NOTICES.md` in binary output is self-contained: its component
copyright, license identity, and license-file locations do not depend on a
link back to a source checkout.

## Automated checks

Before building, check source notices with Windows PowerShell:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Distribution.ps1 -SourceOnly
```

After building, run the full check:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Distribution.ps1
```

The full check verifies that license/provenance files exist, match their source
copies, and accompany the expected runtime payload. CI runs it after building.
Release builds disable compiler debug symbols, and this check rejects common
local account paths embedded in project-built DLLs. Upstream source comments
and full license notices remain intact.
It checks distribution contents; it does not establish byte-identical compiler
output across machines or claim to replace a broader legal review.

`tests/Test-Release.ps1` additionally checks the ZIP checksum and exercises
installation, module loading, real editing, and removal from the extracted
package. See [releasing.md](releasing.md) for the complete release procedure.

The primary upstream terms are the [pinned PSReadLine license](https://github.com/PowerShell/PSReadLine/blob/98d5610f7210924b79f553d982e10a9bd64dd52f/License.txt)
and the Pager license retained under `third-party/`.
