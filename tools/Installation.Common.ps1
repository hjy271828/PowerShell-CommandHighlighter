# Shared installer validation; no profile, module, or policy changes occur here.
function Assert-PlainDirectory([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are not supported in installation paths.' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-PlainTree([string]$Root) {
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point inside installation or source payload.' }
        $item
        if ($item.PSIsContainer) { Get-PlainTree $item.FullName }
    }
}

function Get-OwnedInstallation([string]$Root, [switch]$AllowMissing) {
    Assert-PlainDirectory $Root
    $marker = Join-Path $Root 'commandhighlighter-installation.json'
    $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($state.Product -ne 'PowerShell-CommandHighlighter' -or !$state.Files -or
        $state.Version -notmatch '^\d+\.\d+\.\d+$' -or $state.ModuleVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw 'Invalid installation ownership record.'
    }
    $items = @(Get-PlainTree $Root)
    $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $state.Files) {
        $name = [string]$file.Name
        if (!$name -or [IO.Path]::IsPathRooted($name) -or $name -match '(^|[\\/])\.\.?([\\/]|$)|:' -or
            $name -eq 'commandhighlighter-installation.json' -or !$names.Add($name.Replace('\','/')) -or
            $file.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Unsafe path, duplicate file, or digest in ownership record.' }
        $path = Join-Path $Root $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            if ($AllowMissing) { continue }
            throw 'Installed files are missing. Review before reinstalling.'
        }
        if ((Get-FileHash -LiteralPath $path).Hash -ne $file.Sha256) { throw 'Installed files differ from the ownership record. Review before changing them.' }
    }
    foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point inside installation.' }
        if (!$item.PSIsContainer -and $item.FullName -ne $marker) {
            $relative = $item.FullName.Substring($Root.Length + 1).Replace('\','/')
            if (!$names.Contains($relative)) { throw 'Unowned files exist inside the installation. No files changed.' }
        }
    }
    return $state
}
