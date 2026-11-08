#Requires -Version 5.1
[CmdletBinding()]
param([string]$ArtifactsPath, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (!$ArtifactsPath) { $ArtifactsPath = Join-Path $root 'artifacts' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'artifacts/releases' }
$release = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
if ($release.version -notmatch '^\d+\.\d+\.\d+$') { throw 'release.json must contain a three-part project version.' }
if ($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -ne ('v' + $release.version)) {
    throw 'The Git tag does not match the project release version.'
}
$provenance = Get-Content -LiteralPath (Join-Path $root 'vendor/PSReadLine.provenance.json') -Raw | ConvertFrom-Json
if ($release.moduleVersion -ne $provenance.moduleVersion) { throw 'Release and upstream provenance module versions differ.' }
& "$root/tests/Test-Distribution.ps1" -ArtifactsPath $ArtifactsPath

$stage = Join-Path $root ('.build/release-' + $release.version)
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item $stage -ItemType Directory -Force | Out-Null
$modulePath = 'artifacts/PSReadLine/' + $release.moduleVersion
$moduleSource = Join-Path $ArtifactsPath ('PSReadLine/' + $release.moduleVersion)
# Copy an explicit release inventory. Local installation records, PDBs, build
# caches, and extra files placed in artifacts must not leak into the archive.
$moduleFiles = @(
    'Microsoft.PowerShell.PSReadLine.dll', 'Microsoft.PowerShell.Pager.dll',
    'PSReadLine.psd1', 'PSReadLine.psm1', 'PSReadLine.format.ps1xml',
    'netstd/Microsoft.PowerShell.PSReadLine.Polyfiller.dll',
    'net6plus/Microsoft.PowerShell.PSReadLine.Polyfiller.dll',
    'License.txt', 'CommandHighlighter-LICENSE.txt', 'THIRD-PARTY-NOTICES.md',
    'UPSTREAM.json', 'third-party/Pager-LICENSE.txt',
    'third-party/microsoft.powershell.pager.nuspec'
)
foreach ($relative in $moduleFiles) {
    $target = Join-Path (Join-Path $stage $modulePath) $relative
    New-Item (Split-Path $target -Parent) -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $moduleSource $relative) -Destination $target
}
foreach ($relative in @('install.ps1', 'uninstall.ps1', 'demo.ps1', 'release.json', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $stage
}
# Keep the root notice file's relative third-party directory usable too.
New-Item (Join-Path $stage 'third-party') -ItemType Directory -Force | Out-Null
foreach ($name in @('Pager-LICENSE.txt', 'microsoft.powershell.pager.nuspec')) {
    Copy-Item -LiteralPath (Join-Path $root ('third-party/' + $name)) -Destination (Join-Path $stage 'third-party')
}
Copy-Item -LiteralPath (Join-Path $root 'docs/release-readme.md') -Destination (Join-Path $stage 'README.md')
$notes = Join-Path $root ('docs/releases/v' + $release.version + '.md')
Copy-Item -LiteralPath $notes -Destination (Join-Path $stage 'RELEASE-NOTES.md')

New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$assetName = 'PowerShell-CommandHighlighter-v' + $release.version + '-windows-powershell5.1.zip'
$archive = Join-Path $OutputDirectory $assetName
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive, [IO.Compression.CompressionLevel]::Optimal, $false)
$digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), "$digest  $assetName`n", (New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath $notes -Destination (Join-Path $OutputDirectory 'RELEASE-NOTES.md') -Force
Write-Host "Packaged: $archive"
Write-Host "SHA256: $digest"
