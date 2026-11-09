#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineAssembly,
    [string]$CandidateAssembly,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$CandidateAssembly) {
    $release = Get-Content "$root/release.json" -Raw | ConvertFrom-Json
    $CandidateAssembly = "$root/artifacts/PSReadLine/$($release.moduleVersion)/Microsoft.PowerShell.PSReadLine.dll"
}
# Load the two distinct assembly versions side by side without importing either
# editor module. Both instances use this process's SAME discovery environment.
$baseline = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($BaselineAssembly))
$candidate = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($CandidateAssembly))
$instances = @{
    baseline = [Activator]::CreateInstance($baseline.GetType('PowerShellCommandHighlighter.CommandExistenceHighlighter', $true))
    candidate = [Activator]::CreateInstance($candidate.GetType('PowerShellCommandHighlighter.CommandExistenceHighlighter', $true))
}
$rows = @()
$tokens = $null; $errors = $null
foreach ($scenario in @('cached','cold-valid','cold-missing','typing-cold','typing-cached','long-arguments','many-commands')) {
    $lines = @(switch ($scenario) {
        'cached' { @('Get-Date') }
        'cold-valid' { @('Get-Date', 'Get-ChildItem', 'git') }
        'cold-missing' { @('Get-Datett', 'gittt', 'command-highlighter-nonexistent') }
        'typing-cold' { @('g','gi','git','gitt','gittt','gitt','git','gi') }
        'typing-cached' { @('g','gi','git','gitt','gittt','gitt','git','gi') }
        'long-arguments' { @('Get-Date ' + ('argument ' * 4000)) }
        'many-commands' { @(('Get-Date; ' * 100)) }
    })
    $times = @{ baseline = New-Object 'Collections.Generic.List[double]'; candidate = New-Object 'Collections.Generic.List[double]' }
    # Warm both implementations before collecting samples; cold scenarios still
    # clear the project cache before EACH measured sample, matching v0.1.0.
    for ($i = -8; $i -lt 160; $i++) {
        $line = $lines[($i + 8) % $lines.Count]
        $order = if ($i % 2 -eq 0) { @('baseline','candidate') } else { @('candidate','baseline') }
        foreach ($version in $order) {
            $instance = $instances[$version]
            if ($scenario -like 'cold-*' -or $scenario -eq 'typing-cold') { $instance.Reset() }
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $ast = [Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
            [void]$instance.Analyze($ast, $ExecutionContext)
            $watch.Stop()
            if ($i -ge 0) { $times[$version].Add($watch.Elapsed.TotalMilliseconds) }
        }
    }
    foreach ($version in @('baseline','candidate')) {
        $sorted = @($times[$version] | Sort-Object)
        $rows += [pscustomobject]@{ Scenario=$scenario; Version=$version; Samples=$sorted.Count;
            MedianMs=[Math]::Round($sorted[80],3); P95Ms=[Math]::Round($sorted[151],3); MaxMs=[Math]::Round($sorted[-1],3) }
    }
}
$report = [pscustomobject]@{
    Date=[DateTime]::UtcNow.ToString('yyyy-MM-dd'); PowerShell=$PSVersionTable.PSVersion.ToString()
    BaselineAssemblyVersion=$baseline.GetName().Version.ToString(); CandidateAssemblyVersion=$candidate.GetName().Version.ToString()
    Scope='Parser.ParseInput + Analyze; same process, alternating order, 8 warmup and 160 measured samples per version/scenario; excludes editor rendering and terminal IO'
    Results=$rows
}
if ($OutputPath) { $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$rows | Format-Table -AutoSize
