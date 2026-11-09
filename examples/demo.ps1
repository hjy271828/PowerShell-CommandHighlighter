#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoUserProfile)
$ErrorActionPreference = 'Stop'
# Source checkout: examples/demo.ps1. Binary release: demo.ps1 at package root.
$root = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'release.json')) { $PSScriptRoot } else { Split-Path $PSScriptRoot -Parent }
$artifacts = Join-Path $root 'artifacts'
if (!(Test-Path -LiteralPath "$artifacts/PSReadLine/2.4.5.2/PSReadLine.psd1")) { throw 'Build with tools/build.ps1 or extract the complete binary package first.' }
$savedModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $artifacts + ';' + $savedModulePath
    if ($NoUserProfile) { & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoLogo -NoProfile }
    else { & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoLogo }
} finally { $env:PSModulePath = $savedModulePath }
