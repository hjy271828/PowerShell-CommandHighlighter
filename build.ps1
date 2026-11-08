#Requires -Version 5.1
[CmdletBinding()]
param([string]$Dotnet = 'dotnet', [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$stage = Join-Path $root '.build/upstream'
$output = Join-Path $root 'artifacts/PSReadLine/2.4.5.1'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item $stage -ItemType Directory -Force | Out-Null
Copy-Item "$root/vendor/PSReadLine/*" $stage -Recurse
Copy-Item "$root/src/CommandExistenceHighlighter.cs" "$stage/PSReadLine/CommandExistenceHighlighter.cs"

function Replace-Once([string]$file, [string]$old, [string]$new) {
    $text = [IO.File]::ReadAllText($file)
    if (($text.Split(@($old), [StringSplitOptions]::None).Count - 1) -ne 1) {
        throw "Patch anchor changed in $file. Review upstream before upgrading."
    }
    [IO.File]::WriteAllText($file, $text.Replace($old, $new), (New-Object Text.UTF8Encoding($false)))
}
Replace-Once "$stage/PSReadLine/Render.cs" '            var text = ParseInput();' "            var text = ParseInput();`n            _commandHighlighter.Analyze(_ast, _engineIntrinsics);"
Replace-Once "$stage/PSReadLine/Render.cs" '        private string GetTokenColor(Token token)' @'
        private string GetTokenColor(Token token)
        {
            var commandColor = _commandHighlighter.GetColor(token);
            return commandColor ?? GetDefaultTokenColor(token);
        }

        private string GetDefaultTokenColor(Token token)
'@
Replace-Once "$stage/PSReadLine/ReadLine.cs" '            _engineIntrinsics = engineIntrinsics;' "            _engineIntrinsics = engineIntrinsics;`n            _commandHighlighter.Reset();"
Copy-Item "$root/nuget.config" "$stage/nuget.config"
Replace-Once "$stage/PSReadLine/PSReadLine.csproj" '<AssemblyVersion>2.4.5.0</AssemblyVersion>' '<AssemblyVersion>2.4.5.1</AssemblyVersion>'
Replace-Once "$stage/PSReadLine/PSReadLine.csproj" '<FileVersion>2.4.5</FileVersion>' '<FileVersion>2.4.5.1</FileVersion>'
Replace-Once "$stage/PSReadLine/PSReadLine.csproj" '<InformationalVersion>2.4.5</InformationalVersion>' '<InformationalVersion>2.4.5-commandhighlighter.1</InformationalVersion>'
Replace-Once "$stage/PSReadLine/PSReadLine.psd1" "ModuleVersion = '2.4.5'" "ModuleVersion = '2.4.5.1'"
if ($PrepareOnly) { Write-Host "Prepared guarded source patches: $stage"; return }
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
Write-Host "Built private PSReadLine: $output"
