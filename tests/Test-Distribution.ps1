#Requires -Version 5.1
[CmdletBinding()]
param([string]$ArtifactsPath, [switch]$SourceOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$ArtifactsPath) { $ArtifactsPath = Join-Path $root 'artifacts' }
$sourceFiles = @(
    'LICENSE', 'THIRD-PARTY-NOTICES.md', 'vendor/UPSTREAM.md',
    'vendor/PSReadLine.provenance.json', 'vendor/PSReadLine/License.txt',
    'third-party/Pager-LICENSE.txt', 'third-party/microsoft.powershell.pager.nuspec'
)
foreach ($relative in $sourceFiles) {
    $path = Join-Path $root $relative
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Source distribution notice is missing or empty: $relative"
    }
}
$provenancePath = Join-Path $root 'vendor/PSReadLine.provenance.json'
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($provenance.repository -ne 'https://github.com/PowerShell/PSReadLine' -or
    $provenance.tag -ne 'v2.4.5' -or $provenance.baseVersion -ne '2.4.5' -or
    $provenance.commit -ne '98d5610f7210924b79f553d982e10a9bd64dd52f' -or
    $provenance.license -ne 'BSD-2-Clause') {
    throw 'Upstream provenance changed. Review the pinned source and distribution notices before updating this check.'
}
foreach ($relative in @('README.md', 'vendor/UPSTREAM.md', 'THIRD-PARTY-NOTICES.md')) {
    if (!(Get-Content -LiteralPath (Join-Path $root $relative) -Raw).Contains($provenance.commit)) {
        throw "Full upstream commit is missing from $relative"
    }
}
$psreadlineLicense = Get-Content -LiteralPath (Join-Path $root 'vendor/PSReadLine/License.txt') -Raw
if (!$psreadlineLicense.Contains('Copyright (c) 2013, Jason Shirk') -or
    !$psreadlineLicense.Contains('Redistributions of source code must retain') -or
    !$psreadlineLicense.Contains('Redistributions in binary form must reproduce')) {
    throw 'The upstream copyright notice and both redistribution conditions must be retained.'
}
$pagerLicense = Get-Content -LiteralPath (Join-Path $root 'third-party/Pager-LICENSE.txt') -Raw
if (!$pagerLicense.Contains('Copyright (c) 2020 PowerShell Team') -or
    !$pagerLicense.Contains('The above copyright notice and this permission notice')) {
    throw 'The original Pager MIT license copyright and redistribution notice must be retained.'
}
if ($SourceOnly) { Write-Host 'PASS: source distribution notices and pinned upstream provenance.'; return }

$module = Join-Path $ArtifactsPath ('PSReadLine/' + $provenance.moduleVersion)
$copies = [ordered]@{
    'vendor/PSReadLine/License.txt' = 'License.txt'
    'LICENSE' = 'CommandHighlighter-LICENSE.txt'
    'THIRD-PARTY-NOTICES.md' = 'THIRD-PARTY-NOTICES.md'
    'vendor/PSReadLine.provenance.json' = 'UPSTREAM.json'
    'third-party/Pager-LICENSE.txt' = 'third-party/Pager-LICENSE.txt'
    'third-party/microsoft.powershell.pager.nuspec' = 'third-party/microsoft.powershell.pager.nuspec'
}
foreach ($entry in $copies.GetEnumerator()) {
    $target = Join-Path $module $entry.Value
    if (!(Test-Path -LiteralPath $target -PathType Leaf)) { throw "Binary distribution notice is missing: $($entry.Value)" }
    if ((Get-FileHash -LiteralPath (Join-Path $root $entry.Key)).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Binary distribution notice differs from its source: $($entry.Value)"
    }
}
foreach ($relative in @(
    'Microsoft.PowerShell.PSReadLine.dll', 'Microsoft.PowerShell.Pager.dll',
    'PSReadLine.psd1', 'PSReadLine.psm1', 'PSReadLine.format.ps1xml',
    'netstd/Microsoft.PowerShell.PSReadLine.Polyfiller.dll',
    'net6plus/Microsoft.PowerShell.PSReadLine.Polyfiller.dll'
)) {
    if (!(Test-Path -LiteralPath (Join-Path $module $relative) -PathType Leaf)) { throw "Binary distribution payload is missing: $relative" }
}
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $module 'PSReadLine.psd1')
if ([string]$manifest.ModuleVersion -ne $provenance.moduleVersion) { throw 'Published module version does not match its provenance.' }
Write-Host 'PASS: source and binary distribution licenses, notices, payload, and pinned provenance.'
