#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/tools/Installation.Common.ps1"
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
if (!$InstallRoot) { $InstallRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('WindowsPowerShell/Modules/PSReadLine/' + $release.moduleVersion) }
Assert-PlainDirectory $InstallRoot
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$statePath = Join-Path $InstallRoot 'commandhighlighter-installation.json'
if (!(Test-Path -LiteralPath $statePath)) { Write-Host 'No owned installation found. No files changed.'; return }
$state = Get-OwnedInstallation $InstallRoot -AllowMissing
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if (!$assembly.IsDynamic -and $assembly.Location.StartsWith($InstallRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'This process has loaded the private module. Run uninstall.ps1 from powershell.exe -NoProfile -NonInteractive -File instead.'
    }
}
if (!$PSCmdlet.ShouldProcess($InstallRoot, 'Delete only the owned PSReadLine 2.4.5.2 directory')) { return }
try {
    foreach ($file in Get-ChildItem -LiteralPath $InstallRoot -Recurse -Force -File) {
        $probe = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
    }
} catch {
    throw 'Installation files are in use or not writable. Close shells using this build and retry from a clean process. No module files were removed.'
}
# Keep the ownership record until other files are gone, so an interrupted or
# failed removal can be retried instead of becoming an unowned partial folder.
Get-ChildItem -LiteralPath $InstallRoot -Force | Where-Object FullName -ne $statePath |
    Remove-Item -Recurse -Force
Remove-Item -LiteralPath $statePath -Force
Remove-Item -LiteralPath $InstallRoot -Force
Write-Host 'Uninstalled. Open a NEW PowerShell process to use the original PSReadLine. No profile restoration is needed.'
