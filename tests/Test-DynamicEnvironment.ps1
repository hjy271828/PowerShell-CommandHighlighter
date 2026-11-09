#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$release = Get-Content "$root/release.json" -Raw | ConvertFrom-Json
Import-Module "$root/artifacts/PSReadLine/$($release.moduleVersion)/PSReadLine.psd1"
$highlighter = New-Object PowerShellCommandHighlighter.CommandExistenceHighlighter
$script:checks = 0
function Assert($condition, [string]$label) {
    if (!$condition) { throw "FAIL: $label" }
    $script:checks++
}
function Analyze([string]$text, [switch]$Reset) {
    if ($Reset) { $highlighter.Reset() }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    $highlighter.Analyze($ast, $ExecutionContext)
}
function Check-State([string]$text, [string]$name, $expected) {
    $spans = @(Analyze $text -Reset | Where-Object Name -eq $name)
    Assert ($spans.Count -eq 1) "one span: $text / $name"
    Assert ($spans[0].Exists -ceq $expected) "state: $text / $name"
    if ($null -eq $expected) { Assert ($null -eq $spans[0].Color) "neutral color: $text / $name" }
}
Check-State 'Set-Alias CHFuture Get-Date; CHFuture; Get-Date; CHNeverExists' 'CHFuture' $null
Check-State 'Set-Alias CHFuture Get-Date; CHFuture; Get-Date; CHNeverExists' 'Get-Date' $true
Check-State 'Set-Alias CHFuture Get-Date; CHFuture; Get-Date; CHNeverExists' 'CHNeverExists' $false
Check-State 'Set-Alias -Value Get-Date -Name CHFuture; CHFuture' 'CHFuture' $null
Check-State 'sal CHFuture Get-Date | ForEach-Object { CHFuture; Get-Date }' 'CHFuture' $null
Check-State 'function CHFuture { }; CHFuture; CHNeverExists' 'CHFuture' $null
Check-State 'function CHFuture { CHFuture }' 'CHFuture' $null
Check-State 'CHFuture; function CHFuture { }' 'CHFuture' $false
Check-State '{ Set-Alias CHFuture Get-Date }; CHFuture' 'CHFuture' $false
Check-State 'if ($true) { function CHFuture { } }; CHFuture' 'CHFuture' $null
Check-State 'Import-Module CHFutureModule; Get-CHFuture; Get-Date' 'Get-CHFuture' $null
Check-State 'Import-Module CHFutureModule; Get-CHFuture; Get-Date' 'Get-Date' $true
Check-State '$env:PATH = "pending"; CHFutureExe; Get-Date' 'CHFutureExe' $null
Check-State '$env:PATH = "pending"; CHFutureExe; Get-Date' 'Get-Date' $true
Check-State 'Set-Location pending; & ".\pending.ps1"; Get-Date' '.\pending.ps1' $null
Check-State 'Get-Date | ForEach-Object { Get-Datett }' 'Get-Datett' $false
Check-State '& ".\missing-explicit-script.ps1"' '.\missing-explicit-script.ps1' $false
Check-State 'Set-Alias Get-Date Get-ChildItem; Get-Date' 'Get-Date' $null
Check-State '. { Set-Alias CHFuture Get-Date }; CHFuture; Get-Date' 'CHFuture' $null
Check-State 'function CHDeferred { CHFuture }; function CHFuture { }' 'CHFuture' $null
Check-State 'Set-Alias $computedName Get-Date; CHFuture; Get-Date' 'CHFuture' $null
Check-State 'Set-Alias $computedName Get-Date; CHFuture; Get-Date' 'Get-Date' $true
Check-State '. ".\pending-setup.ps1"; CHFuture; Get-Date' 'CHFuture' $null
Check-State '. ".\pending-setup.ps1"; CHFuture; Get-Date' 'Get-Date' $true
# No statement in the buffer is run, including function definitions or setters.
Assert ($null -eq (Get-Item Alias:/CHFuture -ErrorAction SilentlyContinue)) 'buffer did not create an alias'
Assert ($null -eq (Get-Item Function:/CHFuture -ErrorAction SilentlyContinue)) 'buffer did not create a function'

$oldPath = $env:PATH; $oldExt = $env:PATHEXT; $oldModules = $env:PSModulePath
$oldPreference = Get-Variable PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue
$oldLocation = Get-Location
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ch-dynamic-' + [Guid]::NewGuid().ToString('N'))
New-Item "$temp/modules/CHSideEffect" -ItemType Directory -Force | Out-Null
try {
    Set-Content "$temp/modules/CHSideEffect/CHSideEffect.psd1" "@{RootModule='CHSideEffect.psm1';ModuleVersion='1.0.0';FunctionsToExport=@('Get-CHSideEffect')}"
    Set-Content "$temp/modules/CHSideEffect/CHSideEffect.psm1" '$global:CHImportCount++; function Get-CHSideEffect { $global:CHInvocationCount++ }; Export-ModuleMember -Function Get-CHSideEffect'
    $global:CHImportCount = 0; $global:CHInvocationCount = 0
    $env:PSModulePath = "$temp/modules;" + $oldModules
    $PSModuleAutoLoadingPreference = 'All'
    Check-State 'Get-CHSideEffect' 'Get-CHSideEffect' $true
    Assert ($global:CHImportCount -eq 1 -and $global:CHInvocationCount -eq 0) 'discovery imports initialization but does not invoke command'
    [void](Analyze 'Get-CHSideEffect')
    Assert ($global:CHImportCount -eq 1) 'cached discovery does not repeat initialization'
    Remove-Module CHSideEffect
    $PSModuleAutoLoadingPreference = 'None'
    $spans = @(Analyze 'Get-CHSideEffect')
    Assert ($spans[0].Exists -eq $false -and $global:CHImportCount -eq 1) 'autoload preference invalidates cached result without importing'
    $PSModuleAutoLoadingPreference = 'ModuleQualified'
    Check-State 'Get-CHSideEffect' 'Get-CHSideEffect' $false
    Check-State 'CHSideEffect\Get-CHSideEffect' 'CHSideEffect\Get-CHSideEffect' $true
    Assert ($global:CHImportCount -eq 2 -and $global:CHInvocationCount -eq 0) 'qualified discovery follows session preference'
    Remove-Module CHSideEffect
    $PSModuleAutoLoadingPreference = 'All'
    Import-Module "$temp/modules/CHSideEffect/CHSideEffect.psd1"
    Check-State 'Get-CHSideEffect' 'Get-CHSideEffect' $true
    Check-State 'Remove-Module CHSideEffect; Get-CHSideEffect; Get-Date' 'Get-CHSideEffect' $null
    Check-State 'Remove-Module CHSideEffect; Get-CHSideEffect; Get-Date' 'Get-Date' $true

    Set-Alias CHLiveAlias Get-Date -Scope Global
    Check-State 'CHLiveAlias' 'CHLiveAlias' $true
    Remove-Item Alias:/CHLiveAlias
    [Threading.Thread]::Sleep(280)
    Assert (@(Analyze 'CHLiveAlias')[0].Exists -eq $false) 'alias removal expires after TTL'
    function global:CHLiveFunction { }
    Check-State 'CHLiveFunction' 'CHLiveFunction' $true
    Remove-Item Function:/CHLiveFunction
    $highlighter.Reset()
    Assert (@(Analyze 'CHLiveFunction')[0].Exists -eq $false) 'prompt reset exposes removed function immediately'

    Set-Content "$temp/relative.ps1" '$global:CHInvocationCount++'
    Push-Location $temp
    Check-State '.\relative.ps1' '.\relative.ps1' $true
    Pop-Location
    Assert (@(Analyze '.\relative.ps1')[0].Exists -eq $false) 'location invalidates cached script resolution'
    $env:PATH = $temp
    Copy-Item "$env:SystemRoot/System32/where.exe" "$temp/ch-pathext.exe"
    $env:PATHEXT = '.EXE'
    Check-State 'ch-pathext' 'ch-pathext' $true
    $env:PATHEXT = '.CMD'
    Assert (@(Analyze 'ch-pathext')[0].Exists -eq $false) 'PATHEXT invalidates cached executable'
    $env:PATH = $oldPath; $env:PATHEXT = $oldExt

    $highlighter.Reset()
    $names = @(0..519 | ForEach-Object { 'CHCapacity' + $_ })
    foreach ($name in $names) { Set-Item "Function:global:$name" {} }
    $spans = @(Analyze ($names -join '; '))
    Assert ($spans.Count -eq 520 -and @($spans | Where-Object Exists -ne $true).Count -eq 0) 'more than 512 unique names remain correctly resolved'
    $field = $highlighter.GetType().GetField('cache', [Reflection.BindingFlags]'Instance,NonPublic')
    Assert ($field.GetValue($highlighter).Count -le 512) 'discovery storage remains bounded'
    $highlighter.Reset()
    Assert ($field.GetValue($highlighter).Count -eq 0) 'prompt reset clears bounded cache'
    Assert ($global:CHInvocationCount -eq 0) 'explicit scripts and functions were never invoked'
} finally {
    Set-Location $oldLocation
    $env:PATH = $oldPath; $env:PATHEXT = $oldExt; $env:PSModulePath = $oldModules
    if ($oldPreference) { $PSModuleAutoLoadingPreference = $oldPreference.Value } else { Remove-Variable PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue }
    Remove-Module CHSideEffect -ErrorAction SilentlyContinue
    Remove-Item Alias:/CHLiveAlias, Function:/CHLiveFunction -ErrorAction SilentlyContinue
    foreach ($name in $names) { Remove-Item "Function:/$name" -ErrorAction SilentlyContinue }
    Remove-Variable CHImportCount,CHInvocationCount -Scope Global -ErrorAction SilentlyContinue
    Remove-Item $temp -Recurse -Force
}
Write-Host "PASS: $script:checks dynamic environment, discovery side-effect, and cache checks."
