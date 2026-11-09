#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallRoot,
    [string]$ArtifactsPath
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/tools/Installation.Common.ps1"
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
if (!$InstallRoot) { $InstallRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('WindowsPowerShell/Modules/PSReadLine/' + $release.moduleVersion) }
Assert-PlainDirectory $InstallRoot
if (!$ArtifactsPath) { $ArtifactsPath = Join-Path $PSScriptRoot 'artifacts' }
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this installer in Windows PowerShell 5.1. PowerShell 7 deployment has not been validated.' }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$source = [IO.Path]::GetFullPath((Join-Path $ArtifactsPath ('PSReadLine/' + $release.moduleVersion)))
if (!(Test-Path -LiteralPath "$source/Microsoft.PowerShell.PSReadLine.dll")) { throw 'Build artifacts are missing. Run ./tools/build.ps1 or extract the complete binary release first.' }
$provenance = Get-Content -LiteralPath (Join-Path $source 'UPSTREAM.json') -Raw | ConvertFrom-Json
if ($provenance.moduleVersion -ne $release.moduleVersion) { throw 'Release metadata and module provenance versions differ.' }
if ($provenance.experimental -or (Test-Path -LiteralPath (Join-Path $source 'EXPERIMENTAL-NOT-FOR-DISTRIBUTION.txt'))) { throw 'Experimental upstream probe payload cannot be installed.' }
Assert-PlainDirectory $source
$desiredFiles = @(Get-PlainTree $source | Where-Object { !$_.PSIsContainer })
$statePath = Join-Path $InstallRoot 'commandhighlighter-installation.json'
if (Test-Path -LiteralPath $statePath) {
    $state = Get-OwnedInstallation $InstallRoot
    if ($state.Version -ne $release.version -or $state.Files.Count -ne $desiredFiles.Count) {
        throw 'A different build is already installed at this module version. Review/uninstall it from a clean process before reinstalling.'
    }
    foreach ($file in $desiredFiles) {
        $relative = $file.FullName.Substring($source.Length + 1)
        $installed = Join-Path $InstallRoot $relative
        if (!(Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
            throw 'A different build is already installed at this module version. Review/uninstall it from a clean process before reinstalling.'
        }
    }
    Write-Host 'Already installed. No files changed.'
    return
}
if (Test-Path -LiteralPath $InstallRoot) { throw "Refusing to overwrite an existing directory: $InstallRoot" }
$newer = @(Get-Module PSReadLine -ListAvailable | Where-Object {
    $_.Version -ge ([version]$release.moduleVersion)
})
if ($newer.Count) { throw 'An equal or newer PSReadLine is available. Review/rebase this patch instead of silently shadowing it.' }
if (!$PSCmdlet.ShouldProcess($InstallRoot, 'Add a separate current-user PSReadLine 2.4.5.2 directory; startup will prefer it over 2.4.5')) { return }
$staging = "$InstallRoot.staging-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item $staging -ItemType Directory -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $staging -Recurse
    $files = @(Get-ChildItem -LiteralPath $staging -Recurse -Force -File | ForEach-Object {
        [pscustomobject]@{ Name=$_.FullName.Substring($staging.Length + 1); Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash }
    })
    [ordered]@{Product='PowerShell-CommandHighlighter'; Version=$release.version; Upstream=$provenance.baseVersion; ModuleVersion=$release.moduleVersion; Files=$files} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$staging/commandhighlighter-installation.json" -Encoding UTF8
    [IO.Directory]::Move($staging, $InstallRoot)
} catch {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    throw
}
Write-Host "Installed: $InstallRoot"
Write-Host 'Profile, original modules, execution policy, Oh My Posh theme and WSL configuration were not edited.'
Write-Host 'Open a NEW Windows PowerShell process. Module version 2.4.5.2 should load automatically.'
