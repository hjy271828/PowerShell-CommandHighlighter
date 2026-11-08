#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell/Modules/PSReadLine/2.4.5.1'),
    [string]$ArtifactsPath
)
$ErrorActionPreference = 'Stop'
if (!$ArtifactsPath) { $ArtifactsPath = Join-Path $PSScriptRoot 'artifacts' }
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this installer in Windows PowerShell 5.1. PowerShell 7 deployment has not been validated.' }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$source = [IO.Path]::GetFullPath((Join-Path $ArtifactsPath ('PSReadLine/' + $release.moduleVersion)))
if (!(Test-Path "$source/Microsoft.PowerShell.PSReadLine.dll")) { throw 'Build artifacts are missing. Run ./build.ps1 or extract the complete binary release first.' }
$provenance = Get-Content -LiteralPath (Join-Path $source 'UPSTREAM.json') -Raw | ConvertFrom-Json
if ($provenance.moduleVersion -ne $release.moduleVersion) { throw 'Release metadata and module provenance versions differ.' }
$desiredFiles = @(Get-ChildItem $source -Recurse -File)
$statePath = Join-Path $InstallRoot 'commandhighlighter-installation.json'
if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($state.Product -ne 'PowerShell-CommandHighlighter') { throw 'Ownership marker does not match.' }
    foreach ($file in $state.Files) {
        if (!(Test-Path (Join-Path $InstallRoot $file.Name)) -or (Get-FileHash (Join-Path $InstallRoot $file.Name)).Hash -ne $file.Sha256) {
            throw 'Installed files differ from the ownership record. Review before reinstalling.'
        }
    }
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
if (Test-Path $InstallRoot) { throw "Refusing to overwrite an existing directory: $InstallRoot" }
$newer = @(Get-Module PSReadLine -ListAvailable | Where-Object {
    $_.Version -ge ([version]$release.moduleVersion) -and !(Test-Path (Join-Path $_.ModuleBase 'commandhighlighter-installation.json'))
})
if ($newer.Count) { throw 'An equal or newer PSReadLine is available. Review/rebase this patch instead of silently shadowing it.' }
if (!$PSCmdlet.ShouldProcess($InstallRoot, 'Add a separate current-user PSReadLine 2.4.5.1 directory; startup will prefer it over 2.4.5')) { return }
$staging = "$InstallRoot.staging-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item $staging -ItemType Directory -Force | Out-Null
    Copy-Item "$source/*" $staging -Recurse
    $files = @(Get-ChildItem $staging -Recurse -File | ForEach-Object {
        [pscustomobject]@{ Name=$_.FullName.Substring($staging.Length + 1); Sha256=(Get-FileHash $_.FullName).Hash }
    })
    [ordered]@{Product='PowerShell-CommandHighlighter'; Version=$release.version; Upstream=$provenance.baseVersion; ModuleVersion=$release.moduleVersion; Files=$files} |
        ConvertTo-Json -Depth 5 | Set-Content "$staging/commandhighlighter-installation.json" -Encoding UTF8
    [IO.Directory]::Move($staging, $InstallRoot)
} catch {
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    throw
}
Write-Host "Installed: $InstallRoot"
Write-Host 'Profile, original modules, execution policy, Oh My Posh theme and WSL configuration were not edited.'
Write-Host 'Open a NEW Windows PowerShell process. Module version 2.4.5.1 should load automatically.'
