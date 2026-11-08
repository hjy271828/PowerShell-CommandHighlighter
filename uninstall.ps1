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
Remove-Item -LiteralPath $InstallRoot -Recurse -Force
Write-Host 'Uninstalled. Open a NEW PowerShell process to use the original PSReadLine. No profile restoration is needed.'
