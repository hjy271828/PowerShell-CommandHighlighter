# Technical rationale

## Implementation choice

This project builds a patched PSReadLine, rather than a standalone extension that uses a public token-coloring callback. The inspected baseline is PSReadLine **v2.4.5**, commit `98d5610f7210924b79f553d982e10a9bd64dd52f`.

| Question | Finding for the pinned baseline |
| --- | --- |
| Can public code read the input and AST? | Yes: both `GetBufferState` overloads are present. |
| Can a custom key handler edit and trigger rendering? | Yes: public editing methods such as `Insert` and `Replace` call the renderer. |
| Is there a public per-token foreground-color callback? | None was found in the inspected API or option setters. |
| Does `-Colors Command` validate command existence? | No: it selects the color for a syntax category. |
| Is `CommandValidationHandler` a live rendering callback? | No: it is used by the accept/validation path. |
| Can the existing renderer support this feature with a small patch? | Yes: the private token-color decision can consult an AST-derived command map. |

These conclusions describe the pinned source, not every future PSReadLine version.

## Integration points

1. `GenerateRender` calls the highlighter after `ParseInput`, before the existing prediction rendering path.
2. `GetTokenColor` consults a command span's override color, then falls back to the original implementation.
3. `Initialize` resets discovery state for each new ReadLine call.

The build also marks the assembly and module as **2.4.5.1**, a project-local fork version, not an official upstream release. The guarded substitutions are visible in [the patch](PSReadLine-v2.4.5.patch); the additional implementation is [a single C# file](../src/CommandExistenceHighlighter.cs).

Retaining the original editor avoids intercepting each editing key or drawing a separate terminal overlay. Accepted prediction text becomes ordinary input and is analyzed on the normal rendering path. Unaccepted prediction text does not become part of the analyzed AST.

## Command discovery and side effects

Static `CommandAst` first elements are resolved with the current session's `EngineIntrinsics.InvokeCommand.GetCommand(name, CommandTypes.All)`. This lets PowerShell handle aliases, functions, module discovery, executable extensions, scripts, and explicit command paths.

The implementation does not execute input commands, evaluate dynamic command expressions, start a subprocess per keystroke, or query WSL. **Command discovery may auto-import modules and execute module initialization code.** The feature inherits that behavior from the session's command discovery settings.

Missing commands are red. Discovery exceptions are treated as unknown and retain default syntax coloring. A discoverable command can still fail later because of parameters, permissions, execution policy, installation placeholders, or runtime errors.

A background runspace would not naturally share the current session's functions, aliases, and module state. The current implementation instead uses a bounded cache with a 250 ms TTL, prompt resets, and PATH/PATHEXT/PSModulePath/location invalidation. It does not promise a hard latency bound for cold discovery or slow network paths.

## Startup and installation

The interactive host can load PSReadLine before executing the profile or `-File` startup script. Re-importing a same-identity assembly after startup did not select the patched implementation in integration testing.

The demo therefore adjusts only the child process's module discovery path before launch. Installation adds a separate current-user module version directory, leaving existing module files and profiles untouched. A new shell process is required to select the new version reliably.

## Compatibility and upstream contribution

The APIs used for parsing and discovery are available in Windows PowerShell 5.1. Upstream 2.4.5 targets netstandard2.0 and provides runtime-specific prediction polyfills. This project retains those build inputs, but only Windows PowerShell 5.1 deployment has been validated. PowerShell 7 support must be established by testing rather than inferred from the upstream compatibility claim.

This fork is a prototype for a narrowly scoped feature. A future upstream proposal could discuss either built-in command existence coloring or an extensible semantic coloring API, including cache invalidation, module initialization side effects, color configuration, and latency. This repository does not claim that its current API or installation scheme is suitable for upstream unchanged.

A related request already exists: [PSReadLine issue #3439](https://github.com/PowerShell/PSReadLine/issues/3439). Review that discussion and the [upstream contribution guide](https://github.com/PowerShell/PSReadLine/blob/master/.github/CONTRIBUTING.md) before proposing a duplicate issue or PR.

## Primary references

- [Pinned Render.cs](https://github.com/PowerShell/PSReadLine/blob/v2.4.5/PSReadLine/Render.cs): parsing, token colors, and prediction rendering.
- [Pinned PublicAPI.cs](https://github.com/PowerShell/PSReadLine/blob/v2.4.5/PSReadLine/PublicAPI.cs): input state and editing APIs.
- [Pinned Cmdlets.cs](https://github.com/PowerShell/PSReadLine/blob/v2.4.5/PSReadLine/Cmdlets.cs): fixed color options and validation handler.
- [Pinned BasicEditing.cs](https://github.com/PowerShell/PSReadLine/blob/v2.4.5/PSReadLine/BasicEditing.cs): validation during line acceptance.
- [Set-PSReadLineOption documentation](https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption): public configuration.
- [PSReadLine development notes](https://github.com/PowerShell/PSReadLine#developing-and-contributing): avoiding automatic default-module loading when developing a local build.

PSColor focuses on output coloring and posh-git on Git prompt/completion features, rather than the editor behavior implemented here. Their [project](https://github.com/Davlind/PSColor) [descriptions](https://github.com/dahlbyk/posh-git) were considered during the initial investigation; this is not an exhaustive survey of every third-party project.
