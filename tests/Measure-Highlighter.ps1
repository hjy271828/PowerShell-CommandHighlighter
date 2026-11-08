#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module "$root/artifacts/PSReadLine/2.4.5.1/PSReadLine.psd1"
$highlighter = New-Object PowerShellCommandHighlighter.CommandExistenceHighlighter
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput('Get-Date', [ref]$tokens, [ref]$errors)
[void]$highlighter.Analyze($ast, $ExecutionContext)
$rows = @()
foreach ($scenario in @('cached','cold-valid','cold-missing','typing-cold','typing-cached','long-arguments','many-commands')) {
    $times = @()
    $lines = @(switch ($scenario) {
        'cached' { @('Get-Date') }
        'cold-valid' { @('Get-Date', 'Get-ChildItem', 'git') }
        'cold-missing' { @('Get-Datett', 'gittt', 'command-highlighter-nonexistent') }
        'typing-cold' { @('g','gi','git','gitt','gittt','gitt','git','gi') }
        'typing-cached' { @('g','gi','git','gitt','gittt','gitt','git','gi') }
        'long-arguments' { @('Get-Date ' + ('argument ' * 4000)) }
        'many-commands' { @(('Get-Date; ' * 100)) }
    })
    for ($i = 0; $i -lt 160; $i++) {
        if ($scenario -like 'cold-*' -or $scenario -eq 'typing-cold') { $highlighter.Reset() }
        $line = $lines[$i % $lines.Count]
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $ast = [Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
        [void]$highlighter.Analyze($ast, $ExecutionContext)
        $clock.Stop()
        $times += $clock.Elapsed.TotalMilliseconds
    }
    $sorted = @($times | Sort-Object)
    $rows += [pscustomobject]@{
        Scenario=$scenario; Samples=$times.Count; MedianMs=[Math]::Round($sorted[80],3)
        P95Ms=[Math]::Round($sorted[151],3); MaxMs=[Math]::Round($sorted[-1],3)
    }
}
$report = [pscustomobject]@{
    Date=[DateTime]::UtcNow.ToString('yyyy-MM-dd'); PowerShell=$PSVersionTable.PSVersion.ToString(); PSReadLine=(Get-Module PSReadLine).Version.ToString()
    Scope='Parser.ParseInput + Analyze in Windows PowerShell; excludes terminal IO, prediction, and first process/module startup'
    Results=$rows
}
if ($OutputPath) { $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$rows | Format-Table -AutoSize
