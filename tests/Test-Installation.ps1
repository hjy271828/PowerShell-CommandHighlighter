#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('command-highlighter-install-' + [Guid]::NewGuid().ToString('N'))
New-Item $temp -ItemType Directory | Out-Null
try {
    $policyBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
    $protected = @{}
    foreach ($path in @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)) {
        if (Test-Path -LiteralPath $path) { $protected[$path] = (Get-FileHash -LiteralPath $path).Hash }
    }
    foreach ($module in Get-Module PSReadLine -ListAvailable) {
        $path = Join-Path $module.ModuleBase 'Microsoft.PowerShell.PSReadLine.dll'
        if (Test-Path -LiteralPath $path) { $protected[$path] = (Get-FileHash -LiteralPath $path).Hash }
    }
    $realProfileHash = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
    $install = "$temp/Modules/PSReadLine/2.4.5.2"
    & "$root/install.ps1" -InstallRoot $install -WhatIf
    if (Test-Path $install) { throw 'WhatIf created a module.' }
    & "$root/install.ps1" -InstallRoot $install
    $before = (Get-FileHash "$install/commandhighlighter-installation.json").Hash
    & "$root/install.ps1" -InstallRoot $install
    if ((Get-FileHash "$install/commandhighlighter-installation.json").Hash -ne $before) { throw 'Idempotence failed.' }
    $alternate = Join-Path $temp 'alternate-artifacts'
    Copy-Item "$root/artifacts" $alternate -Recurse
    Add-Content "$alternate/PSReadLine/2.4.5.2/License.txt" 'Test-only desired build difference.'
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
    # Fail closed when local files or ownership paths no longer match.
    Set-Content "$install/unowned.txt" 'must survive'
    $rejected = $false
    try { & "$root/uninstall.ps1" -InstallRoot $install } catch { $rejected = $true }
    if (!$rejected -or !(Test-Path "$install/unowned.txt")) { throw 'Uninstall removed unowned content.' }
    Remove-Item "$install/unowned.txt"
    $record = [IO.File]::ReadAllText("$install/commandhighlighter-installation.json")
    $badState = $record | ConvertFrom-Json
    $badState.Files[0].Name = '../outside.txt'
    Set-Content "$temp/outside.txt" 'outside sentinel'
    $badState | ConvertTo-Json -Depth 5 | Set-Content "$install/commandhighlighter-installation.json"
    $rejected = $false
    try { & "$root/uninstall.ps1" -InstallRoot $install } catch { $rejected = $true }
    if (!$rejected -or (Get-Content "$temp/outside.txt" -Raw).Trim() -ne 'outside sentinel') { throw 'Unsafe ownership path was accepted.' }
    [IO.File]::WriteAllText("$install/commandhighlighter-installation.json", $record, (New-Object Text.UTF8Encoding($false)))
    # A junction must not let an installation escape its owned tree.
    $link = Join-Path $install 'linked'
    New-Item -ItemType Junction -Path $link -Target $temp | Out-Null
    try {
        $rejected = $false
        try { & "$root/uninstall.ps1" -InstallRoot $install } catch { $rejected = $true }
        if (!$rejected -or !(Test-Path "$temp/outside.txt")) { throw 'Reparse point was followed during removal.' }
    } finally { [IO.Directory]::Delete($link) }
    # Model an interrupted previous uninstall: missing owned files are safe to
    # finish removing, while the marker still protects the remaining payload.
    Remove-Item "$install/License.txt"
    & "$root/uninstall.ps1" -InstallRoot $install
    if (Test-Path $install) { throw 'Uninstall did not remove its module.' }
    # A copy failure must leave no destination or staged installation.
    $sourceFile = "$root/artifacts/PSReadLine/2.4.5.2/Microsoft.PowerShell.PSReadLine.dll"
    $sourceLock = [IO.File]::Open($sourceFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $rejected = $false
        try { & "$root/install.ps1" -InstallRoot $install } catch { $rejected = $true }
        if (!$rejected -or (Test-Path $install) -or @(Get-ChildItem (Split-Path $install -Parent) -Filter '*.staging-*').Count) { throw 'Failed install did not roll back.' }
    } finally { $sourceLock.Dispose() }
    # Keep the preceding fork in a separate directory, then remove only the
    # new build. This tests rollback without touching the real user modules.
    $previous = "$temp/Modules/PSReadLine/2.4.5.1"
    New-Item $previous -ItemType Directory -Force | Out-Null
    Set-Content "$previous/keep.txt" 'previous version sentinel'
    & "$root/install.ps1" -InstallRoot $install
    & "$root/uninstall.ps1" -InstallRoot $install
    if (!(Test-Path "$previous/keep.txt")) { throw 'Rollback removed the previous version.' }
    # An equal/newer discoverable module must not be silently shadowed.
    $savedModulePath = $env:PSModulePath
    $conflict = "$temp/conflict/PSReadLine/9.0.0"
    New-Item $conflict -ItemType Directory -Force | Out-Null
    Set-Content "$conflict/PSReadLine.psd1" "@{ModuleVersion='9.0.0';GUID='eb1deef7-e31d-4b49-8441-50cb9a4f4550'}"
    try {
        $env:PSModulePath = "$temp/conflict;" + $savedModulePath
        $rejected = $false
        try { & "$root/install.ps1" -InstallRoot $install } catch { $rejected = $true }
        if (!$rejected -or (Test-Path $install)) { throw 'Version conflict was not rejected.' }
    } finally { $env:PSModulePath = $savedModulePath }
    $literalInstall = "$temp/[literal-install]"
    & "$root/install.ps1" -InstallRoot $literalInstall
    & "$root/install.ps1" -InstallRoot $literalInstall
    & "$root/uninstall.ps1" -InstallRoot $literalInstall
    if (Test-Path -LiteralPath $literalInstall) { throw 'Literal bracket path was not removed.' }
    New-Item $install -ItemType Directory -Force | Out-Null
    Set-Content "$install/keep.txt" 'unowned'
    $rejected = $false
    try { & "$root/install.ps1" -InstallRoot $install } catch { $rejected = $true }
    if (!$rejected -or !(Test-Path "$install/keep.txt")) { throw 'Installer overwrote an unowned directory.' }
    & "$root/uninstall.ps1" -InstallRoot $install
    if (!(Test-Path "$install/keep.txt")) { throw 'Uninstaller deleted an unowned directory.' }
    $after = if (Test-Path $PROFILE.CurrentUserCurrentHost) { (Get-FileHash $PROFILE.CurrentUserCurrentHost).Hash } else { '' }
    if ($after -ne $realProfileHash) { throw 'Real profile changed.' }
    if ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -cne $policyBefore) { throw 'Execution policies changed.' }
    foreach ($path in $protected.Keys) {
        if ((Get-FileHash -LiteralPath $path).Hash -ne $protected[$path]) { throw 'An existing profile or PSReadLine binary changed.' }
    }
    Write-Host 'PASS: install/uninstall, exact-build idempotence, different-build rejection, locked-file protection, WhatIf, ownership protection; path validation, unowned file preservation, reparse rejection, partial uninstall recovery, copy failure rollback, previous-version preservation, version conflict; real profile hash unchanged.'
} finally { Remove-Item $temp -Recurse -Force }
