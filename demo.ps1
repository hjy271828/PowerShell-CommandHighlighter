#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoUserProfile)
$ErrorActionPreference = 'Stop'
$artifacts = Join-Path $PSScriptRoot 'artifacts'
if (!(Test-Path "$artifacts/PSReadLine/2.4.5.1/PSReadLine.psd1")) { throw 'Run build.ps1 first.' }
$savedModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $artifacts + ';' + $savedModulePath
    if ($NoUserProfile) { & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoLogo -NoProfile }
    else { & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoLogo }
} finally { $env:PSModulePath = $savedModulePath }
