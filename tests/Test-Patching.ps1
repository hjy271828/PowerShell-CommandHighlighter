#Requires -Version 5.1
param([string]$Python)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ch-patching-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $temp 'source'; $target = Join-Path $temp 'prepared'
$script:checks = 0
function Assert($condition, [string]$label) {
    if (!$condition) { throw "FAIL: $label" }
    $script:checks++
}
function Reject-Preparation([string]$From, [string]$To) {
    $rejected = $false
    try { & "$root/tools/Prepare-Upstream.ps1" -SourcePath $From -Destination $To | Out-Null } catch { $rejected = $true }
    Assert $rejected 'unsafe preparation rejected'
}
try {
    Copy-Item "$root/vendor/PSReadLine" $source -Recurse -Force
    & "$root/tools/Prepare-Upstream.ps1" -SourcePath $source -Destination $target
    $preparedHash = (Get-FileHash "$target/PSReadLine/Render.cs").Hash
    Reject-Preparation $target "$temp/repeated"
    Assert (!(Test-Path "$temp/repeated")) 'duplicate injection created no destination'
    Reject-Preparation $source $target
    Assert ((Get-FileHash "$target/PSReadLine/Render.cs").Hash -eq $preparedHash) 'existing destination preserved'
    if ($Python) {
        & $Python "$root/tools/prepare_upstream.py" $source "$temp/python"
        if ($LASTEXITCODE) { throw 'Python patch preparation failed.' }
        foreach ($name in @('Render.cs','ReadLine.cs','PSReadLine.csproj','PSReadLine.psd1')) {
            Assert ((Get-FileHash "$target/PSReadLine/$name").Hash -eq (Get-FileHash "$temp/python/PSReadLine/$name").Hash) "Windows/Python byte parity: $name"
        }
    }
    $entry = (Get-Content "$root/tools/patches.json" -Raw | ConvertFrom-Json)[-1]
    $path = Join-Path $source $entry.file
    $original = [IO.File]::ReadAllText($path).Replace("`r`n","`n")
    foreach ($text in @($original.Replace($entry.before, ''), ($original + $entry.before), $original.Replace('private void Initialize(Runspace', 'private void Different(Runspace'))) {
        [IO.File]::WriteAllText($path, $text)
        Reject-Preparation $source "$temp/rejected"
        Assert (!(Test-Path "$temp/rejected")) 'late hook failure leaves no partial destination'
        Assert (!(Get-Content "$source/PSReadLine/Render.cs" -Raw).Contains('_commandHighlighter')) 'input source was not modified'
    }
    [IO.File]::WriteAllText($path, $original)
    $project = "$source/PSReadLine/PSReadLine.csproj"
    $originalProject = [IO.File]::ReadAllText($project)
    [IO.File]::WriteAllText($project, $originalProject.Replace('<FileVersion>2.4.5</FileVersion>', '<FileVersion>2.9.0</FileVersion>'))
    Reject-Preparation $source "$temp/metadata"
    Assert (!(Test-Path "$temp/metadata")) 'metadata drift cannot partially patch'
    Assert (@(Get-ChildItem $temp -Filter '*.pending-*').Count -eq 0) 'failed preparation cleaned staging folders'
    Write-Host "PASS: $script:checks patch atomicity, context, duplicate injection and metadata checks. PythonParity=$([bool]$Python)"
} finally {
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
