param([string]$SnapshotPath, [switch]$UseUserProfile, [switch]$UseInstalledModule)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$UseInstalledModule) { Import-Module "$root/artifacts/PSReadLine/2.4.5.1/PSReadLine.psd1" }
if ($UseUserProfile) { . $PROFILE.CurrentUserCurrentHost }
else {
    function global:prompt { 'CH> ' }
    Set-PSReadLineOption -Colors @{Command='#4CAF50';Error='#FF6688';Parameter='#78B9F5';String='#E6B86A';Variable='#C6A6F7';InlinePrediction='#777777'}
    Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
}
Set-PSReadLineOption -HistorySaveStyle SaveNothing -PredictionSource History -PredictionViewStyle InlineView
$global:CHSnapshotPath = $SnapshotPath
Set-PSReadLineKeyHandler -Key F12 -ScriptBlock {
    $text = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$text,[ref]$cursor)
    $t = [Microsoft.PowerShell.PSConsoleReadLine]
    $i = $t.GetField('_singleton',[Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
    $lines = $t.GetField('_consoleBufferLines',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($i)
    [pscustomobject]@{ Text=$text; Cursor=$cursor; Lines=@($lines | ForEach-Object ToString) } |
        ConvertTo-Json -Depth 4 | Set-Content ($global:CHSnapshotPath + '.new') -Encoding UTF8
    Move-Item ($global:CHSnapshotPath + '.new') $global:CHSnapshotPath -Force
}
Write-Host 'CH_READY'
