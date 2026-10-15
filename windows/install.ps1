<#
.SYNOPSIS
    Bootstrap a Windows machine from these dotfiles (the counterpart of
    `make install` on macOS).

.DESCRIPTION
    Idempotent; safe to re-run after pulling. Steps:
      1. winget packages from windows/winget.json
      2. the PSFzf module for PowerShell 7
      3. $PROFILE stub that dot-sources windows/powershell/profile.ps1
      4. ~/.gitconfig including windows/git/.gitconfig
      5. ~/.claude/CLAUDE.md importing claude/.claude/CLAUDE.md
      6. Windows Terminal: merge windows/terminal/settings.json into its settings

    Nothing is symlinked (that needs Developer Mode or admin): each target is
    a small stub pointing back into this clone, so edits here apply directly.

    Runs under Windows PowerShell 5.1 on a fresh machine: after winget installs
    PowerShell 7 it re-launches itself there for the remaining steps.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows\install.ps1
#>
[CmdletBinding()]
param(
    [switch] $SkipPackages
)
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Win = Join-Path $Repo 'windows'

function Step($msg) { Write-Host "-> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "ok $msg" -ForegroundColor Green }

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Write a stub file, keeping a backup of whatever else was there.
function Set-Stub($path, $content) {
    if ((Test-Path $path) -and ((Get-Content $path -Raw) -eq $content)) {
        Ok $path; return
    }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    if (Test-Path $path) {
        Copy-Item $path "$path.bak" -Force
        Write-Host "  (previous file kept as $path.bak)"
    }
    [IO.File]::WriteAllText($path, $content)
    Ok "$path -> repo"
}

# --- 1. packages (in whichever PowerShell we started in) ----------------------
if (-not $SkipPackages) {
    Step 'winget packages'
    winget import --import-file (Join-Path $Win 'winget.json') `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    # winget exits non-zero when some packages were already installed; the
    # following steps check for what they need.
    Update-Path
}

# --- the rest runs in PowerShell 7 ---------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # winget may install it machine-wide (MSI) or per user (MSIX, exposed
    # through the WindowsApps alias), so look it up on PATH.
    $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { throw 'PowerShell 7 (pwsh.exe) not found on PATH; did winget fail?' }
    $rest = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-SkipPackages')
    & $pwsh @rest
    exit $LASTEXITCODE
}

# --- 2. PowerShell modules -----------------------------------------------------
Step 'PowerShell modules'
if (Get-Module -ListAvailable PSFzf) { Ok 'PSFzf' }
else {
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module PSFzf -Scope CurrentUser
    Ok 'PSFzf'
}

# --- 3. profile ----------------------------------------------------------------
Step 'PowerShell profile'
$profileSrc = Join-Path $Win 'powershell\profile.ps1'
Set-Stub $PROFILE.CurrentUserAllHosts ". '$profileSrc'`r`n"

# --- 4. git --------------------------------------------------------------------
Step 'git'
$gitInclude = (Join-Path $Win 'git\.gitconfig') -replace '\\', '/'
$includes = @(git config --global --get-all include.path)
if ($includes -contains $gitInclude) { Ok "~/.gitconfig includes $gitInclude" }
else {
    git config --global --add include.path $gitInclude
    Ok "~/.gitconfig includes $gitInclude"
}

# --- 5. Claude Code ------------------------------------------------------------
Step 'Claude Code'
$claudeSrc = (Join-Path $Repo 'claude\.claude\CLAUDE.md') -replace '\\', '/'
Set-Stub (Join-Path $HOME '.claude\CLAUDE.md') "@$claudeSrc`n"

# --- 6. Windows Terminal -------------------------------------------------------
Step 'Windows Terminal'
$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (-not (Test-Path $wtSettings)) {
    Write-Host '  settings.json not found: open Windows Terminal once, then re-run.' -ForegroundColor Yellow
}
else {
    # Recursively merge $src into $dst; arrays of named objects (schemes) are
    # upserted by name, every other value is replaced.
    function Merge-Object($dst, $src) {
        foreach ($p in $src.PSObject.Properties) {
            $cur = $dst.PSObject.Properties[$p.Name]
            if ($cur -and $cur.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) {
                Merge-Object $cur.Value $p.Value
            }
            elseif ($cur -and $cur.Value -is [array] -and $p.Value -is [array] -and $p.Value[0].name) {
                $merged = [Collections.ArrayList]@($cur.Value | Where-Object { $_.name -notin $p.Value.name })
                $merged.AddRange(@($p.Value))
                $dst.($p.Name) = @($merged)
            }
            else {
                $dst | Add-Member -Force -NotePropertyName $p.Name -NotePropertyValue $p.Value
            }
        }
    }
    $settings = Get-Content $wtSettings -Raw | ConvertFrom-Json
    $overlay = Get-Content (Join-Path $Win 'terminal\settings.json') -Raw | ConvertFrom-Json
    Merge-Object $settings $overlay
    $json = $settings | ConvertTo-Json -Depth 32
    if ($json -eq ((Get-Content $wtSettings -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 32)) {
        Ok $wtSettings
    }
    else {
        Copy-Item $wtSettings "$wtSettings.bak" -Force
        [IO.File]::WriteAllText($wtSettings, $json)
        Ok "$wtSettings (previous kept as settings.json.bak)"
    }
}

Write-Host "`nDone. Open a new Windows Terminal tab to pick everything up." -ForegroundColor Green
