# Changelog

## 0.1.0 - Unreleased

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
