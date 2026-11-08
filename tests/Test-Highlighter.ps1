#Requires -Version 5.1
[CmdletBinding()]
param([string]$ArtifactsPath)
$ErrorActionPreference = 'Stop'
if (!$ArtifactsPath) { $ArtifactsPath = Join-Path $PSScriptRoot '../artifacts' }
if ('Microsoft.PowerShell.PSConsoleReadLine' -as [type]) { throw 'Run this test in a fresh powershell.exe -NoProfile process.' }
Import-Module "$ArtifactsPath/PSReadLine/2.4.5.1/PSReadLine.psd1"
$script:checks = 0
function Assert($condition, [string]$message) {
    if (!$condition) { throw "FAIL: $message" }
    $script:checks++
}
$highlighter = New-Object PowerShellCommandHighlighter.CommandExistenceHighlighter
function Analyze([string]$line, [switch]$Reset) {
    if ($Reset) { $highlighter.Reset() }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
    $highlighter.Analyze($ast, $ExecutionContext)
}
function Check([string]$line, [string[]]$names, [bool[]]$exists) {
    $result = @(Analyze $line -Reset)
    Assert ($result.Count -eq $names.Count) "span count: $line ($($result.Count))"
    for ($i = 0; $i -lt $names.Count; $i++) {
        Assert ($result[$i].Name -ceq $names[$i]) "command name: $line"
        Assert ($null -ne $result[$i].Exists -and $result[$i].Exists -eq $exists[$i]) "existence: $line / $($names[$i])"
    }
}
$gitExists = $null -ne $ExecutionContext.InvokeCommand.GetCommand('git', [Management.Automation.CommandTypes]::All)
$pythonExists = $null -ne $ExecutionContext.InvokeCommand.GetCommand('python', [Management.Automation.CommandTypes]::All)
Check 'Get-Date' @('Get-Date') @($true)
Check 'Get-Datett' @('Get-Datett') @($false)
Check 'Get-ChildItem' @('Get-ChildItem') @($true)
Check 'Get-ChildItemttt' @('Get-ChildItemttt') @($false)
Check 'ls' @('ls') @($true)
Check 'dir' @('dir') @($true)
Check 'git' @('git') @($gitExists)
Check 'gittt' @('gittt') @($false)
Check 'python --version' @('python') @($pythonExists)
Check 'git status --short' @('git') @($gitExists)
Check 'ls nonexistent' @('ls') @($true)
Check 'Get-ChildItem | Where-Object Name' @('Get-ChildItem','Where-Object') @($true,$true)
Check 'git; python' @('git','python') @($gitExists,$pythonExists)
Check 'if ($true) { Get-Date }' @('Get-Date') @($true)
Check '"git"' @() @()
Check '# gittt' @() @()
Check '$variable' @() @()
Check '' @() @()
Check 'Get-Date |' @('Get-Date') @($true)
Check "Get-Date`nGet-ChildItem" @('Get-Date','Get-ChildItem') @($true,$true)
Check '& "Get-Date"' @('Get-Date') @($true)
Check "& 'Get-Datett'" @('Get-Datett') @($false)
Check '& $command' @() @()
Check '& ("Get-Date")' @() @()
Check '"$(Get-Date)"' @('Get-Date') @($true)
Check '& "git$version"' @() @()
Check '& { Get-Date }' @('Get-Date') @($true)
Check 'Get-Dat' @('Get-Dat') @($false)
# Parse errors/partial syntax must be safe while the user is still typing.
foreach ($partial in @('&', 'if (', 'Get-Date "', "& 'Get-Date", '$(', '"$(')) { [void](Analyze $partial -Reset); $script:checks++ }
function global:CHTestFunction { 'not executed' }
try {
    Set-Alias CHTestAlias CHTestFunction -Scope Global
    Check 'CHTestFunction' @('CHTestFunction') @($true)
    Check 'CHTestAlias' @('CHTestAlias') @($true)
    Check 'CHNewAlias' @('CHNewAlias') @($false)
    Set-Alias CHNewAlias Get-Date -Scope Global
    Check 'CHNewAlias' @('CHNewAlias') @($true)
    [void](Analyze 'CHTTLFunction' -Reset)
    function global:CHTTLFunction { }
    [Threading.Thread]::Sleep(280)
    $ttlResult = @(Analyze 'CHTTLFunction')
    Assert ($ttlResult[0].Exists -eq $true) 'negative cache expires within a prompt'
    Remove-Item Function:/CHTTLFunction
    [Threading.Thread]::Sleep(280)
    $ttlResult = @(Analyze 'CHTTLFunction')
    Assert ($ttlResult[0].Exists -eq $false) 'positive cache expires within a prompt'
} finally {
    Remove-Item Function:/CHTestFunction -ErrorAction SilentlyContinue
    Remove-Item Alias:/CHTestAlias, Alias:/CHNewAlias -ErrorAction SilentlyContinue
}

# Real Windows discovery of scripts, Unicode paths, PATH changes and new binaries.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('command-highlighter-tests-' + [Guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$oldModulePath = $env:PSModulePath
New-Item $temp -ItemType Directory | Out-Null
Push-Location $temp
try {
    New-Item "$temp/modules/CHTestModule" -ItemType Directory -Force | Out-Null
    Set-Content "$temp/modules/CHTestModule/CHTestModule.psm1" 'function Get-CHTestModuleCommand { }; Export-ModuleMember -Function Get-CHTestModuleCommand'
    Set-Content "$temp/modules/CHTestModule/CHTestModule.psd1" "@{RootModule='CHTestModule.psm1';ModuleVersion='1.0.0';FunctionsToExport=@('Get-CHTestModuleCommand')}"
    $env:PSModulePath = "$temp/modules;" + $oldModulePath
    Check 'Get-CHTestModuleCommand' @('Get-CHTestModuleCommand') @($true)
    Assert ($null -ne (Get-Module CHTestModule)) 'engine discovered and autoloaded module'
    $unicodeName = ([string][char]0x6D4B) + [char]0x8BD5 + ' script.ps1'
    Set-Content -LiteralPath $unicodeName -Value "'not executed'" -Encoding UTF8
    $literal = "& '.\$unicodeName'"
    Check $literal @(".\$unicodeName") @($true)
    Check '.\missing.exe' @('.\missing.exe') @($false)
    Check ("& '" + (Join-Path $temp $unicodeName) + "'") @((Join-Path $temp $unicodeName)) @($true)
    $env:PATH = $temp
    Check 'git' @('git') @($false)
    Check 'ch-installed' @('ch-installed') @($false)
    Copy-Item "$env:SystemRoot/System32/where.exe" "$temp/ch-installed.exe"
    Check 'ch-installed' @('ch-installed') @($true)
    $env:PATH = $oldPath
    Check 'git' @('git') @($gitExists)
    [void](Analyze 'git' -Reset)
    $env:PATH = $temp
    $pathResult = @(Analyze 'git')
    Assert ($pathResult[0].Exists -eq $false) 'PATH invalidates without prompt reset'
    $env:PATH = $oldPath
    $pathResult = @(Analyze 'git')
    Assert ($pathResult[0].Exists -eq $gitExists) 'PATH restoration invalidates without prompt reset'
} finally {
    $env:PATH = $oldPath
    $env:PSModulePath = $oldModulePath
    Remove-Module CHTestModule -ErrorAction SilentlyContinue
    Pop-Location
    Remove-Item $temp -Recurse -Force
}

# Test the ACTUAL patched GenerateRender/GetTokenColor path, not colored Write-Host.
$type = [Microsoft.PowerShell.PSConsoleReadLine]
$private = [Reflection.BindingFlags]'Instance,NonPublic'
$singleton = $type.GetField('_singleton', [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
$type.GetField('_engineIntrinsics', $private).SetValue($singleton, $ExecutionContext)
Set-PSReadLineOption -PredictionSource None -HistorySaveStyle SaveNothing -Colors @{
    String='#E6B86A'; Variable='#C6A6F7'; Parameter='#78B9F5'; InlinePrediction='#777777'
}
function Render([string]$text) {
    $buffer = $type.GetField('_buffer', $private).GetValue($singleton)
    [void]$buffer.Clear(); [void]$buffer.Append($text)
    $type.GetField('_tokens', $private).SetValue($singleton, $null)
    $method = $type.GetMethod('GenerateRender', $private)
    [void]$method.Invoke($singleton, @(''))
    $lines = $type.GetField('_consoleBufferLines', $private).GetValue($singleton)
    ($lines | ForEach-Object ToString) -join "`n"
}
$green = [PowerShellCommandHighlighter.CommandExistenceHighlighter]::ExistingColor
$red = [PowerShellCommandHighlighter.CommandExistenceHighlighter]::MissingColor
foreach ($text in @('Get-Datett','Get-Datet','Get-Date','Get-Datett','Get-Date')) {
    $rendered = Render $text
    $expected = if ($text -eq 'Get-Date') { $green } else { $red }
    Assert ($rendered.Contains($expected + $text)) "actual render after edits: $text"
}
Assert ((Render 'gittt --short').Contains(([char]27 + '[38;2;120;185;245m') + '--short')) 'parameter keeps original color'
Assert ((Render '"gittt"').Contains(([char]27 + '[38;2;230;184;106m') + '"gittt"')) 'standalone string keeps original color'
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $false
Assert (!(Render 'Get-Datett').Contains($red)) 'disable restores normal coloring'
[PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled = $true
Write-Host "PASS: $script:checks checks. Windows PowerShell $($PSVersionTable.PSVersion); git=$gitExists; python=$pythonExists"
