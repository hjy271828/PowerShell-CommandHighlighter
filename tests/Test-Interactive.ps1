#Requires -Version 5.1
[CmdletBinding()]
param([switch]$UseUserProfile, [switch]$UseInstalledModule, [string]$TranscriptPath)
$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/ConPtyHarness.cs"
$snapshotFile = Join-Path ([IO.Path]::GetTempPath()) ('ch-snapshot-' + [Guid]::NewGuid().ToString('N') + '.json')
$exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$command = '"' + $exe + '" -NoLogo -NoProfile -NoExit -File "' + "$PSScriptRoot\Start-Interactive.ps1" + '" -SnapshotPath "' + $snapshotFile + '"'
if ($UseUserProfile) { $command += ' -UseUserProfile' }
if ($UseInstalledModule) { $command += ' -UseInstalledModule' }
$savedModulePath = $env:PSModulePath
try {
    # The interactive host imports PSReadLine BEFORE -File or the profile runs.
    # Make the private module discoverable before starting that host process.
    if (!$UseInstalledModule) { $env:PSModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts') + ';' + $savedModulePath }
    $pty = New-Object CommandHighlighterConPty($command, (Split-Path $PSScriptRoot -Parent))
} finally { $env:PSModulePath = $savedModulePath }
$script:checks = 0
$esc = [string][char]27
$green = $esc + '[38;2;76;175;80m'
$red = $esc + '[38;2;255;102;136m'
function Send([string]$text) { $pty.Send($text); Start-Sleep -Milliseconds 180 }
function Snapshot {
    Remove-Item $snapshotFile -ErrorAction SilentlyContinue
    Send ($esc + '[24~')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (!(Test-Path $snapshotFile) -and $watch.Elapsed.TotalSeconds -lt 8) { Start-Sleep -Milliseconds 50 }
    if (!(Test-Path $snapshotFile)) { throw "Snapshot timeout. Transcript: $($pty.Transcript)" }
    Get-Content $snapshotFile -Raw | ConvertFrom-Json
}
function Check([string]$text,[string]$color,[string]$label) {
    $s = Snapshot
    if ($s.Text -cne $text -or !(($s.Lines -join "`n").Contains($color))) { throw "FAIL: $label. $($s | ConvertTo-Json -Compress)" }
    $script:checks++
}
function Reset-Input { Send ([string][char]3) }
try {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (!$pty.Transcript.Contains('CH_READY') -and $watch.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 100 }
    if (!$pty.Transcript.Contains('CH_READY')) { throw "Startup failed: $($pty.Transcript)" }
    Start-Sleep -Milliseconds 500
    # Seed through a real accepted line after ReadLine has initialized history.
    Send "Get-Date -Format yyyy`r"
    Send 'Get-Dat'
    Check 'Get-Dat' $red 'incomplete command word'
    Send 'e'
    Check 'Get-Date' $green 'typing changes red to green'
    $prediction = Snapshot
    if (!(($prediction.Lines -join '').Contains($esc + '[38;2;119;119;119m'))) { throw 'Gray inline prediction missing.' }
    $script:checks++
    Send 't'
    Check 'Get-Datet' $red 'typing changes green to red'
    Send ([string][char]127)
    Check 'Get-Date' $green 'Backspace returns to green'
    Send ($esc + '[C')
    Check 'Get-Date -Format yyyy' $green 'RightArrow accepts suggestion'
    Reset-Input
    Send 'Get-Datett'
    Send ($esc + '[D' + $esc + '[D' + $esc + '[3~' + $esc + '[3~')
    Check 'Get-Date' $green 'cursor movement and Delete'
    Reset-Input
    Send 'Get-Dat'
    Send "`t"
    $completed = Snapshot
    if (!$completed.Text.StartsWith('Get-Date') -or !(($completed.Lines -join '').Contains($green))) { throw 'Tab completion failed.' }
    $script:checks++
    Reset-Input
    Send 'Get-Date'
    Send 't'
    Send ([string][char]26)
    Check 'Get-Date' $green 'Undo'
    Send ([string][char]25)
    Check 'Get-Datet' $red 'Redo'
    Reset-Input
    Send 'Get-Datett'
    Send ([string][char]1)
    Send 'Get-Date'
    Check 'Get-Date' $green 'Ctrl+A then replace selection'
    Reset-Input
    Send 'Get-Date'
    Send "`r"
    Send ($esc + '[A')
    Check 'Get-Date' $green 'history UpArrow'
    Reset-Input
    Send ([string][char]18)
    Send 'Get-Date'
    Send $esc
    Check 'Get-Date' $green 'Ctrl+R history search'
    Reset-Input
    Send 'if ($true) {'
    Send "`r"
    Send 'Get-Date'
    Check "if (`$true) {`nGet-Date" $green 'multiline editing'
    Reset-Input
    Send 'Get-Date; gittt --short | Where-Object Name'
    $pipeline = Snapshot
    $render = $pipeline.Lines -join ''
    if (!$render.Contains($green + 'Get-Date') -or !$render.Contains($red + 'gittt') -or !$render.Contains($green + 'Where-Object')) { throw 'Pasted pipeline/multiple command colors failed.' }
    $script:checks++
    if (!$pty.Transcript.Contains($green) -or !$pty.Transcript.Contains($red)) { throw 'No actual colored output reached the pseudoconsole.' }
    $script:checks++
    Write-Host "PASS: $script:checks real Windows ConPTY checks. UseUserProfile=$UseUserProfile; UseInstalledModule=$UseInstalledModule"
} finally {
    if ($TranscriptPath) { [IO.File]::WriteAllText($TranscriptPath, $pty.Transcript, (New-Object Text.UTF8Encoding($false))) }
    $pty.Dispose()
    Remove-Item $snapshotFile, ($snapshotFile + '.new') -ErrorAction SilentlyContinue
}
