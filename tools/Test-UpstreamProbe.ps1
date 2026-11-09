#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Discovery, [Parameter(Mandatory)][string]$Report)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$inputReport = Get-Content -LiteralPath $Discovery -Raw | ConvertFrom-Json
$result = [ordered]@{ target=$inputReport.target; ref=$inputReport.ref; commit=$inputReport.commit; experimental=$true; status='failed'; phase='preparation'; diagnostic='' }
$work = Join-Path $root ('.build/probe-work-' + $inputReport.target)
try {
    if ($inputReport.status -ne 'ready') { throw 'Upstream inputs are unavailable.' }
    # Build and test in a throwaway project copy, keeping the supported vendor
    # tree and artifacts completely separate from experimental compilation.
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item $work -ItemType Directory -Force | Out-Null
    foreach ($name in @('src','tools','tests','vendor','third-party')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $work -Recurse }
    foreach ($name in @('release.json','nuget.config','global.json','LICENSE','THIRD-PARTY-NOTICES.md')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $work }
    $result.phase = 'patch'
    & "$work/tools/build.ps1" -PrepareOnly -UpstreamPath $inputReport.source -Experimental
    $result.phase = 'build'
    & "$work/tools/build.ps1" -UpstreamPath $inputReport.source -Experimental
    $result.phase = 'semantic-and-dynamic-tests'
    foreach ($test in @('Test-Highlighter','Test-DynamicEnvironment','Test-Interactive')) {
        & powershell.exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $work ('tests/' + $test + '.ps1'))
        if ($LASTEXITCODE) { throw "Experimental $test failed (exit $LASTEXITCODE)." }
    }
    $result.status = 'passed'
    $result.phase = 'complete'
} catch {
    # Avoid putting runner/account paths or raw terminal output in the summary.
    $result.diagnostic = ($_.Exception.Message -replace '(?i)[a-z]:[\\/][^\r\n]*', '<local path>')
    Write-Host "::notice::Experimental upstream probe failed during $($result.phase); see diagnostic artifact."
} finally {
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report -Encoding UTF8
    # Never upload DLLs, even on failure. Diagnostic JSON is the only cached result.
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
