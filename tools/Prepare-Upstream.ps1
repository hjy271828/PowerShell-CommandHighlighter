#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$Destination,
    [switch]$Experimental
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = (Get-Content -LiteralPath "$root/release.json" -Raw | ConvertFrom-Json).moduleVersion
$plan = Get-Content -LiteralPath "$PSScriptRoot/patches.json" -Raw | ConvertFrom-Json
$texts = @{}
# Validate the complete plan in memory before touching the destination. Context
# anchors bind each hook to its intended method, not just a matching statement.
foreach ($entry in $plan) {
    if (!$texts.ContainsKey($entry.file)) {
        $texts[$entry.file] = [IO.File]::ReadAllText((Join-Path $SourcePath $entry.file)).Replace("`r`n", "`n")
        if ($texts[$entry.file].Contains('_commandHighlighter') -or $texts[$entry.file].Contains('GetDefaultTokenColor')) {
            throw "Source already patched: $($entry.file)"
        }
    }
    $text = $texts[$entry.file]
    $count = $text.Split(@([string]$entry.before), [StringSplitOptions]::None).Count - 1
    if ($count -ne 1) { throw "Patch anchor mismatch: $($entry.file); expected 1, found $count. Review upstream context." }
    $texts[$entry.file] = $text.Replace([string]$entry.before, [string]$entry.after)
}
$metadata = @(
    @('PSReadLine/PSReadLine.csproj', '<AssemblyVersion>', '</AssemblyVersion>', '2.4.5.0', $version),
    @('PSReadLine/PSReadLine.csproj', '<FileVersion>', '</FileVersion>', '2.4.5', $version),
    @('PSReadLine/PSReadLine.csproj', '<InformationalVersion>', '</InformationalVersion>', '2.4.5', ('2.4.5-commandhighlighter.' + $version.Split('.')[-1])),
    @('PSReadLine/PSReadLine.psd1', "ModuleVersion = '", "'", '2.4.5', $version)
)
foreach ($item in $metadata) {
    $file, $prefix, $suffix, $expected, $replacement = $item
    if (!$texts.ContainsKey($file)) { $texts[$file] = [IO.File]::ReadAllText((Join-Path $SourcePath $file)).Replace("`r`n", "`n") }
    $pattern = [regex]::Escape($prefix) + '([^<\r\n'']+)' + [regex]::Escape($suffix)
    $matches = [regex]::Matches($texts[$file], $pattern)
    if ($matches.Count -ne 1 -or (!$Experimental -and $matches[0].Groups[1].Value -ne $expected)) {
        throw "Version anchor mismatch: $file / $prefix. Review upstream metadata."
    }
    $texts[$file] = $texts[$file].Replace($matches[0].Value, ($prefix + $replacement + $suffix))
}
if (Test-Path -LiteralPath (Join-Path $SourcePath 'PSReadLine/CommandExistenceHighlighter.cs')) { throw 'Injected source already exists.' }
if (Test-Path -LiteralPath $Destination) { throw 'Preparation destination must not exist; existing staged source was preserved.' }
$pending = "$Destination.pending-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item $pending -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SourcePath '*') -Destination $pending -Recurse
    foreach ($file in $texts.Keys) { [IO.File]::WriteAllText((Join-Path $pending $file), $texts[$file], (New-Object Text.UTF8Encoding($false))) }
    Copy-Item -LiteralPath "$root/src/CommandExistenceHighlighter.cs" -Destination (Join-Path $pending 'PSReadLine/CommandExistenceHighlighter.cs')
    Copy-Item -LiteralPath "$root/nuget.config" -Destination (Join-Path $pending 'nuget.config')
    [IO.Directory]::Move($pending, $Destination)
} finally {
    if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Recurse -Force }
}
Write-Host 'PASS: complete guarded patch plan prepared.'
