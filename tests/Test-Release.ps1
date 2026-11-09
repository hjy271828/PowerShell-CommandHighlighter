#Requires -Version 5.1
[CmdletBinding()]
param([string]$ReleaseDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$ReleaseDirectory) { $ReleaseDirectory = Join-Path $root 'artifacts/releases' }
$release = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$name = 'PowerShell-CommandHighlighter-v' + $release.version + '-windows-powershell5.1.zip'
$archive = Join-Path $ReleaseDirectory $name
$expected = ((Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'SHA256SUMS.txt') -Raw).Trim() -split '\s+', 2)
if ($expected.Count -ne 2 -or $expected[1] -ne $name -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected[0]) {
    throw 'Release archive checksum or filename does not match SHA256SUMS.txt.'
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('command-highlighter-release-' + [Guid]::NewGuid().ToString('N'))
$unpacked = Join-Path $temporary 'unpacked'
$install = Join-Path $temporary ('Modules/PSReadLine/' + $release.moduleVersion)
$powershell = Join-Path $PSHOME 'powershell.exe'
$savedModulePath = $env:PSModulePath
$profileHash = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
try {
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $metadata = Get-Content -LiteralPath (Join-Path $unpacked 'release.json') -Raw | ConvertFrom-Json
    if ($metadata.version -ne $release.version -or $metadata.moduleVersion -ne $release.moduleVersion) {
        throw 'Release ZIP metadata does not match the source release version.'
    }
    foreach ($relative in @('install.ps1','uninstall.ps1','demo.ps1','README.md','RELEASE-NOTES.md','LICENSE','THIRD-PARTY-NOTICES.md')) {
        if (!(Test-Path -LiteralPath (Join-Path $unpacked $relative) -PathType Leaf)) { throw "Release ZIP is missing $relative" }
    }
    $expectedRoot = @(
        'install.ps1', 'uninstall.ps1', 'tools/Installation.Common.ps1', 'demo.ps1', 'release.json', 'README.md',
        'RELEASE-NOTES.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'CHANGELOG.md',
        'third-party/Pager-LICENSE.txt', 'third-party/microsoft.powershell.pager.nuspec'
    )
    $expectedModule = @(
        'Microsoft.PowerShell.PSReadLine.dll', 'Microsoft.PowerShell.Pager.dll',
        'PSReadLine.psd1', 'PSReadLine.psm1', 'PSReadLine.format.ps1xml',
        'netstd/Microsoft.PowerShell.PSReadLine.Polyfiller.dll',
        'net6plus/Microsoft.PowerShell.PSReadLine.Polyfiller.dll', 'License.txt',
        'CommandHighlighter-LICENSE.txt', 'THIRD-PARTY-NOTICES.md', 'UPSTREAM.json',
        'third-party/Pager-LICENSE.txt', 'third-party/microsoft.powershell.pager.nuspec'
    ) | ForEach-Object { 'artifacts/PSReadLine/' + $release.moduleVersion + '/' + $_ }
    $actual = @(Get-ChildItem $unpacked -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($unpacked.Length + 1).Replace('\', '/')
    })
    if (@(Compare-Object @($expectedRoot + $expectedModule) $actual).Count) {
        throw 'Release ZIP differs from the declared file inventory.'
    }
    & "$root/tests/Test-Distribution.ps1" -ArtifactsPath (Join-Path $unpacked 'artifacts')
    & "$unpacked/install.ps1" -InstallRoot $install -WhatIf
    if (Test-Path -LiteralPath $install) { throw 'Release WhatIf installation wrote a module.' }
    & "$unpacked/install.ps1" -InstallRoot $install
    $state = Get-Content -LiteralPath (Join-Path $install 'commandhighlighter-installation.json') -Raw | ConvertFrom-Json
    if ($state.Version -ne $release.version -or $state.ModuleVersion -ne $release.moduleVersion) {
        throw 'Installed release ownership metadata has inconsistent versions.'
    }
    & $powershell -NoLogo -NoProfile -NonInteractive -File "$root/tests/Invoke-ReleaseSmoke.ps1" -ManifestPath (Join-Path $install 'PSReadLine.psd1') -ExpectedVersion $release.moduleVersion
    if ($LASTEXITCODE) { throw 'Installed release smoke test failed.' }
    # Only the test process tree sees this temporary module search directory.
    $env:PSModulePath = (Join-Path $temporary 'Modules') + ';' + $savedModulePath
    & $powershell -NoLogo -NoProfile -NonInteractive -File "$root/tests/Test-Interactive.ps1" -UseInstalledModule
    if ($LASTEXITCODE) { throw 'Installed release ConPTY integration check failed.' }
    $env:PSModulePath = $savedModulePath
    & $powershell -NoLogo -NoProfile -NonInteractive -File "$unpacked/uninstall.ps1" -InstallRoot $install
    if ($LASTEXITCODE -or (Test-Path -LiteralPath $install)) { throw 'Extracted release uninstall failed.' }
    $after = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
    if ($after -ne $profileHash) { throw 'Release installation changed the existing profile.' }
    Write-Host 'PASS: release checksum, extraction, notices, temporary installation, real editing, and removal.'
} finally {
    $env:PSModulePath = $savedModulePath
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
