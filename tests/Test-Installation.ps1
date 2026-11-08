#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('command-highlighter-install-' + [Guid]::NewGuid().ToString('N'))
New-Item $temp -ItemType Directory | Out-Null
try {
    $realProfileHash = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
    $install = "$temp/Modules/PSReadLine/2.4.5.1"
    & "$root/install.ps1" -InstallRoot $install -WhatIf
    if (Test-Path $install) { throw 'WhatIf created a module.' }
    & "$root/install.ps1" -InstallRoot $install
    $before = (Get-FileHash "$install/commandhighlighter-installation.json").Hash
    & "$root/install.ps1" -InstallRoot $install
    if ((Get-FileHash "$install/commandhighlighter-installation.json").Hash -ne $before) { throw 'Idempotence failed.' }
    $alternate = Join-Path $temp 'alternate-artifacts'
    Copy-Item "$root/artifacts" $alternate -Recurse
    Add-Content "$alternate/PSReadLine/2.4.5.1/License.txt" 'Test-only desired build difference.'
    $installedLicense = (Get-FileHash "$install/License.txt").Hash
    $differentBuildRejected = $false
    try { & "$root/install.ps1" -InstallRoot $install -ArtifactsPath $alternate } catch { $differentBuildRejected = $true }
    if (!$differentBuildRejected -or (Get-FileHash "$install/License.txt").Hash -ne $installedLicense) {
        throw 'Installer silently reused or overwrote a different desired build.'
    }
    & "$root/uninstall.ps1" -InstallRoot $install -WhatIf
    if (!(Test-Path $install)) { throw 'WhatIf deleted a module.' }
    $lock = [IO.File]::Open("$install/Microsoft.PowerShell.PSReadLine.dll", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $lockedRemovalRejected = $false
        try { & "$root/uninstall.ps1" -InstallRoot $install } catch { $lockedRemovalRejected = $true }
        if (!$lockedRemovalRejected -or !(Test-Path "$install/Microsoft.PowerShell.PSReadLine.dll") -or
            (Get-FileHash "$install/commandhighlighter-installation.json").Hash -ne $before) {
            throw 'Locked module removal did not preserve the ownership record and payload.'
        }
    } finally { $lock.Dispose() }
    & "$root/uninstall.ps1" -InstallRoot $install
    if (Test-Path $install) { throw 'Uninstall did not remove its module.' }
    New-Item $install -ItemType Directory -Force | Out-Null
    Set-Content "$install/keep.txt" 'unowned'
    $rejected = $false
    try { & "$root/install.ps1" -InstallRoot $install } catch { $rejected = $true }
    if (!$rejected -or !(Test-Path "$install/keep.txt")) { throw 'Installer overwrote an unowned directory.' }
    & "$root/uninstall.ps1" -InstallRoot $install
    if (!(Test-Path "$install/keep.txt")) { throw 'Uninstaller deleted an unowned directory.' }
    $after = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
    if ($after -ne $realProfileHash) { throw 'Real profile changed.' }
    Write-Host 'PASS: install/uninstall, exact-build idempotence, different-build rejection, locked-file protection, WhatIf, ownership protection; real profile hash unchanged.'
} finally { Remove-Item $temp -Recurse -Force }
