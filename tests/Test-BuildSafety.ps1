#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$release = Get-Content "$root/release.json" -Raw | ConvertFrom-Json
$output = "$root/artifacts/PSReadLine/$($release.moduleVersion)"
$before = @{}
foreach ($file in Get-ChildItem $output -Recurse -File) { $before[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName).Hash }
if (!$before.Count) { throw 'Build a valid module before testing publication safety.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ch-build-failure-' + [Guid]::NewGuid().ToString('N'))
New-Item $temp -ItemType Directory | Out-Null
try {
    foreach ($code in @(17, 0)) {
        # Exit 17 models compilation failure; exit 0 without output models a
        # compiler producing no required payload. Neither may replace artifacts.
        $fake = Join-Path $temp 'compiler.ps1'
        Set-Content $fake "exit $code"
        $rejected = $false
        try { & "$root/tools/build.ps1" -Dotnet $fake } catch { $rejected = $true }
        if (!$rejected) { throw 'Incomplete build was accepted.' }
        foreach ($path in $before.Keys) {
            if (!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $before[$path]) { throw 'Failed build changed published artifacts.' }
        }
    }
    $marker = Join-Path $output 'EXPERIMENTAL-NOT-FOR-DISTRIBUTION.txt'
    try {
        Set-Content -LiteralPath $marker 'Test-only experimental marker.'
        $packageRejected = $false; $installRejected = $false
        try { & "$root/tools/package.ps1" } catch { $packageRejected = $true }
        try { & "$root/install.ps1" -InstallRoot "$temp/install" } catch { $installRejected = $true }
        if (!$packageRejected -or !$installRejected -or (Test-Path "$temp/install")) { throw 'Experimental output escaped the distribution boundary.' }
    } finally { Remove-Item -LiteralPath $marker -Force }
    Write-Host 'PASS: compiler failure and incomplete payload preserve the preceding complete build; experimental payloads cannot be packaged or installed.'
} finally {
    Remove-Item $temp -Recurse -Force
    if (Test-Path "$output.pending") { Remove-Item "$output.pending" -Recurse -Force }
}
