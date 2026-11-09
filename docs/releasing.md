# Release procedure

The latest published preview is **[v0.1.1](https://github.com/hjy271828/PowerShell-CommandHighlighter/releases/tag/v0.1.1)**,
released on **2026-11-09**. The project version is 0.1.1, while the patched
PSReadLine module version is 2.4.5.2. They describe different components and
should not be confused with upstream v2.4.5.

Use this procedure for future releases. Examples below use v0.1.1; replace the
version and release summary with the next reviewed release when preparing it.

## Prepare the source commit

1. Keep `release.json`, the intended `v<version>` tag, the matching file under
   `docs/releases/`, and the changelog consistent.
2. Build and run the checks documented in the README. Keep the changelog entry
   marked unreleased until the actual release is published, then record its
   publication date without inventing an earlier release.
3. Commit and push the reviewed source changes. Check the CI run for that exact
   commit. GitHub-hosted outcomes must be verified separately from local results.

No publishing step is built into CI. The workflow only builds, tests, packages,
and uploads an Actions artifact using read-only repository permissions.

## Produce and verify the binary ZIP

On Windows PowerShell 5.1 with .NET SDK 8.x:

```powershell
.\tools\build.ps1
.\tools\package.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tests\Test-Release.ps1
```

Alternatively, download `release-assets` from the successful CI run. Extract
the Actions artifact wrapper to obtain the named binary ZIP, `SHA256SUMS.txt`,
and `RELEASE-NOTES.md` inside it. Upload those files to the release rather than
the Actions wrapper archive.

`Test-Release.ps1` verifies the checksum, extracts the package, checks notices,
installs into a temporary module directory, loads it in a fresh process, runs
real ConPTY editing checks against that installation, and removes it. It checks
that the existing user profile was preserved. It does not install into the
normal user module directory.

`tools/package.ps1` includes only the declared payload and user scripts. Runtime DLLs,
the original licenses, `UPSTREAM.json`, release metadata, and standalone usage
instructions travel together. Generated files are ignored by Git.

For a local integrity check:

```powershell
Get-FileHash .\artifacts\releases\PowerShell-CommandHighlighter-v0.1.1-windows-powershell5.1.zip -Algorithm SHA256
Get-Content .\artifacts\releases\SHA256SUMS.txt
```

Checksums detect file differences; they are not an Authenticode signature.
The preview binaries and scripts are not signed. The included README explains
how to unblock reviewed downloaded files without changing execution policy.

## Create the GitHub draft

1. Select the source commit whose workflow and artifacts passed. Create the
   matching `v<version>` tag on that commit, not on an older commit that lacks release
   scripts or on an unreviewed later commit.
2. Draft a release titled `v<version> - <summary>`, such as the published
   `v0.1.1 - Hardening preview`.
3. Paste the prepared `RELEASE-NOTES.md` and attach the named ZIP and
   `SHA256SUMS.txt` from that same build.
4. Mark **This is a pre-release**, as recorded in `release.json`.
5. Review the tag, version, assets, checksums, supported shell, and known
   limitations before publishing the draft.

GitHub's automatic source ZIP/tarball does not include the ignored compiled
artifacts. The separately attached binary ZIP is the no-SDK installation path.

A release follows repository read permissions. A private repository's release
does not become publicly downloadable simply because it was published. Choose
repository visibility separately; this project's scripts never change it.
See [GitHub's release access documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
and [draft/publish instructions](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

## After publishing

1. Verify the published tag, release status, named ZIP and checksums against the
   successful CI run for the tagged commit.
2. Replace the released version's `Unreleased` changelog heading with its actual
   publication date. Update the README download link and validation record.
3. Submit those documentation changes as a normal follow-up commit. Keep the
   published tag and release assets fixed so their source and checksums remain
   reproducible; the published archives retain their original documentation.
4. Keep `release.json` aligned with the published project/module versions and
   pre-release status until preparing a new release. Start a new changelog
   section when there are actual changes to record for the next version.
