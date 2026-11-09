#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem $root -File -Filter *.ps1) + @(Get-ChildItem "$root/tests" -File -Filter *.ps1) + @(Get-ChildItem "$root/tools" -File -Filter *.ps1) + @(Get-ChildItem "$root/examples" -File -Filter *.ps1)
foreach ($file in $files) {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "Syntax error in $($file.Name): $errors" }
}
& "$root/tools/build.ps1" -PrepareOnly
foreach ($name in @('PSReadLine/Render.cs','PSReadLine/ReadLine.cs','PSReadLine/PSReadLine.csproj','PSReadLine/PSReadLine.psd1')) {
    if (!(Test-Path "$root/.build/upstream/$name")) { throw "Prepared file missing: $name" }
}
Write-Host "PASS: $($files.Count) project scripts parse in Windows PowerShell 5.1; native PowerShell build preparation completed."
