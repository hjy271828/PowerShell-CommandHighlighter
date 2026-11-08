#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
Import-Module -Name $ManifestPath -ErrorAction Stop
$loaded = Get-Module PSReadLine
if ([string]$loaded.Version -ne $ExpectedVersion) { throw 'Installed release selected the wrong module version.' }
if (![PowerShellCommandHighlighter.CommandExistenceHighlighter]::Enabled) { throw 'Installed release did not enable highlighting.' }
$highlighter = New-Object PowerShellCommandHighlighter.CommandExistenceHighlighter
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput('Get-Date; Get-Datett', [ref]$tokens, [ref]$errors)
$spans = @($highlighter.Analyze($ast, $ExecutionContext))
if ($spans.Count -ne 2 -or $spans[0].Exists -ne $true -or $spans[1].Exists -ne $false) {
    throw 'Installed release command discovery smoke check failed.'
}
Write-Host 'PASS: extracted and installed release loads with correct command discovery.'
