#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell/Modules/PSReadLine/2.4.5.1'))
$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$statePath = Join-Path $InstallRoot 'commandhighlighter-installation.json'
if (!(Test-Path $statePath)) { Write-Host 'No owned installation found. No files changed.'; return }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
if ($state.Product -ne 'PowerShell-CommandHighlighter') { throw 'Ownership marker does not match.' }
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if (!$assembly.IsDynamic -and $assembly.Location.StartsWith($InstallRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'This process has loaded the private module. Run uninstall.ps1 from powershell.exe -NoProfile -NonInteractive -File instead.'
    }
}
if (!$PSCmdlet.ShouldProcess($InstallRoot, 'Delete only the owned PSReadLine 2.4.5.1 directory')) { return }
try {
    foreach ($file in Get-ChildItem -LiteralPath $InstallRoot -Recurse -File -Filter *.dll) {
        $probe = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
    }
} catch {
    throw 'Module DLLs are in use or not writable. Close shells using this build and retry from a clean process. No module files were removed.'
}
# Keep the ownership record until other files are gone, so an interrupted or
# failed removal can be retried instead of becoming an unowned partial folder.
Get-ChildItem -LiteralPath $InstallRoot -Force | Where-Object FullName -ne $statePath |
    Remove-Item -Recurse -Force
Remove-Item -LiteralPath $statePath -Force
Remove-Item -LiteralPath $InstallRoot -Force
Write-Host 'Uninstalled. Open a NEW PowerShell process to use the original PSReadLine. No profile restoration is needed.'
