# Vendored source provenance

- Project: [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine)
- Tag: `v2.4.5`
- Commit: `98d5610f7210924b79f553d982e10a9bd64dd52f`
- License: BSD-2-Clause; see [PSReadLine/License.txt](PSReadLine/License.txt)

The retained `PSReadLine/` and `Polyfill/` build files are unmodified upstream
code; Git may normalize line endings according to `.gitattributes`. The unused
upstream test suite, Visual Studio solution, and local IDE launch configuration
are not included in this subset. Original file-level copyright notices and the
complete upstream license are preserved. Machine-readable identifiers are in
[PSReadLine.provenance.json](PSReadLine.provenance.json); the same file is copied
to binary distributions as `UPSTREAM.json`.

Build staging adds `src/CommandExistenceHighlighter.cs` and applies three guarded
integration changes: analyze the parsed AST during rendering, consult command
colors before the existing token-color logic, and clear state at each ReadLine
initialization. Module and assembly metadata mark the build as `2.4.5.2` with
an informational version of `2.4.5-commandhighlighter.2`.

These are project-local identifiers, not an official PSReadLine release. See
[the generated review patch](../docs/PSReadLine-v2.4.5.patch). Builds fail if an
expected upstream anchor changes.
