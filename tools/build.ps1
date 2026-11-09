#Requires -Version 5.1
[CmdletBinding()]
param([string]$Dotnet = 'dotnet', [switch]$PrepareOnly, [string]$UpstreamPath, [switch]$Experimental)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $root '.build/upstream'
$version = (Get-Content -LiteralPath "$root/release.json" -Raw | ConvertFrom-Json).moduleVersion
$final = Join-Path $root ('artifacts/PSReadLine/' + $version)
$output = "$final.pending"
if ($UpstreamPath -and !$Experimental) { throw 'Alternate upstream sources require the experimental probe mode.' }
if (!$UpstreamPath) { $UpstreamPath = Join-Path $root 'vendor/PSReadLine' }
$candidate = "$stage.pending"
if (Test-Path $candidate) { Remove-Item $candidate -Recurse -Force }
& "$root/tools/Prepare-Upstream.ps1" -SourcePath $UpstreamPath -Destination $candidate -Experimental:$Experimental
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
[IO.Directory]::Move($candidate, $stage)
if ($PrepareOnly) { Write-Host "Prepared guarded source patches: $stage"; return }
foreach ($required in @('Polyfill/Polyfill.csproj','PSReadLine/PSReadLine.csproj')) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $required))) { throw "Required upstream build input missing: $required. Build layout changed; manual rebase required." }
}

foreach ($framework in @('netstandard2.0', 'net6.0')) {
    & $Dotnet publish "$stage/Polyfill/Polyfill.csproj" -c Release -f $framework --nologo -p:DebugType=None -p:DebugSymbols=false -p:UseSharedCompilation=false -m:1
    if ($LASTEXITCODE) { throw "Polyfill build failed: $LASTEXITCODE" }
}
& $Dotnet publish "$stage/PSReadLine/PSReadLine.csproj" -c Release --nologo -p:DebugType=None -p:DebugSymbols=false -p:UseSharedCompilation=false -m:1
if ($LASTEXITCODE) { throw "PSReadLine build failed: $LASTEXITCODE" }
if (Test-Path $output) { Remove-Item $output -Recurse -Force }
New-Item "$output/netstd", "$output/net6plus" -ItemType Directory -Force | Out-Null
foreach ($file in @('Microsoft.PowerShell.PSReadLine.dll', 'Microsoft.PowerShell.Pager.dll', 'PSReadLine.psd1', 'PSReadLine.psm1', 'PSReadLine.format.ps1xml')) {
    Copy-Item "$stage/PSReadLine/bin/Release/netstandard2.0/publish/$file" $output
}
Copy-Item "$stage/Polyfill/bin/Release/netstandard2.0/publish/Microsoft.PowerShell.PSReadLine.Polyfiller.dll" "$output/netstd/"
Copy-Item "$stage/Polyfill/bin/Release/net6.0/publish/Microsoft.PowerShell.PSReadLine.Polyfiller.dll" "$output/net6plus/"
Copy-Item "$stage/License.txt" $output
Copy-Item "$root/third-party" "$output/third-party" -Recurse
Copy-Item "$root/LICENSE" "$output/CommandHighlighter-LICENSE.txt"
Copy-Item "$root/THIRD-PARTY-NOTICES.md" $output
Copy-Item "$root/vendor/PSReadLine.provenance.json" "$output/UPSTREAM.json"
if ($Experimental) {
    Set-Content -LiteralPath (Join-Path $output 'EXPERIMENTAL-NOT-FOR-DISTRIBUTION.txt') -Value 'Unreviewed upstream probe. Do not install, package, or publish.'
    $probeProvenance = Get-Content -LiteralPath (Join-Path $output 'UPSTREAM.json') -Raw | ConvertFrom-Json
    $probeProvenance | Add-Member -NotePropertyName experimental -NotePropertyValue $true
    $probeProvenance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'UPSTREAM.json') -Encoding UTF8
}
# Publish only a complete payload, restoring the previous build if rename fails.
$backup = "$final.previous"
if (Test-Path -LiteralPath $backup) { throw 'Previous build backup exists; review before rebuilding.' }
try {
    if (Test-Path -LiteralPath $final) { [IO.Directory]::Move($final, $backup) }
    [IO.Directory]::Move($output, $final)
} catch {
    if ((Test-Path -LiteralPath $backup) -and !(Test-Path -LiteralPath $final)) { [IO.Directory]::Move($backup, $final) }
    throw
}
if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }

Write-Host "Built private PSReadLine: $final"
