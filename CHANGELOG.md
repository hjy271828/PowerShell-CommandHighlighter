# Changelog

## 0.1.1 - Unreleased

- Group build/package/internal scripts under tools and the source demo under examples.

- Preflight a shared context patch plan and all metadata before staging changes.
- Preserve complete build artifacts on compiler and payload failure.
- Use neutral highlighting for recognized pending command-environment changes.
- Invalidate discovery caching when module autoload preferences change.
- Retain the 250 ms TTL and 512-name capacity, with dynamic/side-effect regression coverage.
- Add weekly isolated tag/master probes, diagnostic caching and bounded network handling.
- Reject packaging experimental probe output; never update vendor automatically.
- Harden installation ownership, literal paths, reparse checks and interrupted removal.
- Install the new module as 2.4.5.2 alongside 2.4.5.1 to support rollback.
- Expand real Windows PowerShell 5.1 interaction, failure and performance validation.

## 0.1.0 - 2026-11-08

- Add live command existence colors through a small PSReadLine 2.4.5 rendering patch.
- Resolve static command names in the current PowerShell session with bounded caching.
- Provide separate current-user module installation, removal, and a temporary demo session.
- Add semantic/render checks, a real ConPTY integration harness, and benchmarks.
- Document Windows PowerShell 5.1 validation and unverified compatibility boundaries.
- Record the exact upstream commit in the README and binary provenance metadata.
- Verify full license/notice distribution for source archives and compiled modules.
- Package a no-SDK Windows preview ZIP with checksums and standalone instructions.
- Test installation, real editing, and removal from the extracted release ZIP.
- Reject reuse of a different build installed under the same module version.
- Omit compiler debug symbols and check project binaries for local account paths.
- Detect locked DLLs before removal and retain uninstall ownership metadata until last.
