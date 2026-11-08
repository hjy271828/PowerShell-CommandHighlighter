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
    & "$root/uninstall.ps1" -InstallRoot $install -WhatIf
    if (!(Test-Path $install)) { throw 'WhatIf deleted a module.' }
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
    Write-Host 'PASS: install/uninstall, idempotence, WhatIf, ownership protection; real profile hash unchanged.'
} finally { Remove-Item $temp -Recurse -Force }
