# v0.1.1 hardening review

The supported baseline remains PSReadLine v2.4.5 at commit
`98d5610f7210924b79f553d982e10a9bd64dd52f`, on Windows PowerShell 5.1.
Project version 0.1.1 uses a separate module directory, 2.4.5.2.
Source entry points are grouped under `tools/` and `examples/`; only install/
uninstall remain at the root. Binary packages retain a root demo entry point. This does not
claim compatibility with a newer upstream release or PowerShell 7.

## Patch safety

The original builders independently replaced seven text anchors, writing each
replacement before validating the next one. A late mismatch left partial staged
source. Python's old checks also used `assert`, which optimization can disable.

The builders now share `tools/patches.json` for the three rendering/lifecycle
hooks. Windows preparation and the WSL helper validate the entire plan and all
four version fields in memory, require exactly one match, reject existing
injections, then write a fresh temporary tree. Hook anchors include the method
signature and neighboring statements. No vendor file is edited. An existing
preparation destination is rejected. Build output is replaced only after the
complete runtime payload and notices have been collected; a failed rename
restores the previous build. Concurrent builds in one checkout are unsupported.

Regression tests damage the last hook, duplicate anchors, change a method's
context, drift metadata, attempt reinjection, compare Windows/Python output,
and simulate compiler failure and missing publish output. These cases preserve
inputs and existing complete artifacts. No fuzzy or partial patch is accepted.

A unified diff was considered: `git apply --check` can preflight context, but
requires Git in the Windows build path and needs separately reviewed version
substitutions. Roslyn could identify methods structurally, but adds compiler
packages/tooling without proving the unchanged rendering contracts are safe.
The demonstrated defects are addressed by complete preflight, context anchors,
shared data and negative tests; neither alternative justified a larger rewrite.
The review diff remains available in `PSReadLine-v2.4.5.patch`.

## Three command states

`CommandSpan.Exists` remains nullable: true means discovered, false means not
found, and null means unknown. Null supplies no foreground override: PSReadLine
uses the user's existing syntax color. It is not a configurable third color.
Dynamic invocation expressions remain unevaluated and have no command span.

A buffer is not an executed session. A recognized pending alias definition or
function definition makes the affected command name neutral. Other names still
receive independent green/red results. This applies across semicolons,
pipelines and nested scopes; deferred function bodies and literal dot-sourced
blocks receive conservative handling. Definitions inside an unrelated literal
script block do not affect the outer input.

Pending imports, dot-sourced scripts, location changes and PATH/PATHEXT/PSModulePath assignments make
missing or search-dependent commands neutral while retaining known session
cmdlets/functions/aliases. A recognized `Remove-Module` makes commands belonging
to that module neutral. Built-in alias spellings such as `sal` and `ipmo` are
recognized; module-qualified setters are also handled.

This is bounded static analysis, not a PowerShell interpreter. Arbitrary script
side effects, custom aliases for setters, provider operations, abbreviated
parameters, reflection, computed names and every branch/scope interaction cannot
be predicted. Module initialization can itself change arbitrary session state.
Green still means discoverable in the current session, not guaranteed runtime
success. Conservative neutral results are intentional when a recognized
mutation affects discovery; unrelated commands are not globally disabled.

## Discovery, caching and side effects

The active-session `InvokeCommand.GetCommand(name, CommandTypes.All)` behavior
is retained. Tests use an isolated module with separate initialization and
function-invocation counters: discovery can import and initialize a module,
while the exported function is never invoked. Repeated cached lookup does not
repeat initialization. Tests cover `All`, `None`, and `ModuleQualified`
autoload preferences. The feature does not temporarily change that preference.

The 250 ms TTL and 512-name capacity are unchanged. Reset at the next ReadLine
exposes prompt-time alias/function/module changes. Tests cover positive and
negative expiry, alias removal, reset, more than 512 distinct names, PATH,
PATHEXT, current location, and PSModulePath-driven discovery. Changing
`PSModuleAutoLoadingPreference` now also clears cached results immediately.
Within one prompt, unobserved alias/function/module changes can remain stale
until expiry or an explicit cache reset. Cold lookup remains synchronous;
network paths, discovery hooks and module initialization can block the editor.

The primary references are Microsoft's [GetCommand API](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.commandinvocationintrinsics.getcommand)
and [command precedence documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence?view=powershell-5.1).
These document discovery semantics; the side-effect claims above are also
verified directly on Windows PowerShell 5.1 rather than inferred from PowerShell 7.

## Experimental upstream probes

`upstream-compatibility.yml` runs weekly on Monday at 03:37 UTC or manually.
GitHub runs scheduled workflows from the default branch, so scheduling becomes
active after this change is merged. See [GitHub's schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
The supported pinned build/tests run first. Latest semantic tag and master are
separate experimental targets, each pinned to the full SHA returned by GitHub.
Tag selection examines the first 100 tags, including previews; a new preview is
not automatically a supported baseline.

Discovery records changes/missing files against the retained baseline subset.
It verifies archive paths before extraction and retries transient network/server
failures at most three times with bounded timeouts. HTTP 403/429 is reported as
unavailable without sleeping until a potentially distant quota reset. The
read-only API token is not passed to downloaded code or the archive host.

Each available target is patched, built, and subjected to semantic, dynamic and
real ConPTY tests in an isolated throwaway copy. Diagnostics distinguish patch,
build and test failures. Experimental output has a marker that `tools/package.ps1`
rejects. DLLs are deleted and never uploaded or installed by the probe.

Only diagnostic JSON is cached, keyed by upstream SHA and project source/tests/
workflow hashes. An unchanged tested combination reuses the result, including
a known incompatibility. Cache eviction can cause a harmless repeated probe.
The manual `force` input bypasses reuse for a fresh experiment. No Issues,
comments or releases are created. Experimental incompatibility is a
notice/summary rather than a repeated failed-job notification. An infrastructure
failure still fails its workflow step; a green experimental job alone does not
mean compatibility. Read the JSON status, phase and diagnostic. Unavailable
inputs are explicitly skipped, not reported as passing.

## Installation and rollback

The current-user installation, profile preservation and no-administrator
workflow are unchanged. v0.1.1 installs into 2.4.5.2; v0.1.0's 2.4.5.1 and other
upstream versions are preserved. Close shells using the new build and remove
2.4.5.2 to roll back; a fresh shell uses the next eligible installed version.
No automatic in-place upgrade or deletion of earlier versions occurs.

Both scripts validate ownership paths/digests, reject traversal, duplicates,
reparse points and additional unowned files, and use literal file access.
The uninstaller checks the existing owned files before deletion and permits
already-missing files so interrupted removal can be retried. File locks are
checked before removing payload files. A local actor changing files after
validation can still race the script; this is not a security boundary against
another process running as the same user.

Tests exercise clean install, exact repeat, modified builds, locked files,
unowned directories/files, malformed ownership, junctions, partial removal,
copy failure cleanup, newer-version conflicts and previous-version retention.
They also verify existing profile/module hashes and execution policies remain
unchanged, without recording their private paths or contents in reports.
