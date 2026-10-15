# PowerShell 7 profile — the native-Windows counterpart of zsh/.zshrc.
# $PROFILE itself is a one-line stub (written by windows/install.ps1) that
# dot-sources this file, so it stays versioned here without symlinks.
#
#   zsh (macOS)                here
#   zsh-autosuggestions     -> PSReadLine inline prediction (accept: RightArrow / End)
#   zsh-syntax-highlighting -> PSReadLine (built in)
#   fzf-tab                 -> PSFzf on Tab; Ctrl+R history, Ctrl+T files
#   Pure                    -> Starship with the pure preset (windows/starship.toml)

# --- line editing ------------------------------------------------------------
# Predictions need a real console; skip them when output is redirected.
if (-not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
}
Set-PSReadLineOption -HistoryNoDuplicates -MaximumHistoryCount 50000
# Up/Down search history by the typed prefix, as oh-my-zsh does.
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Chord Ctrl+d -Function DeleteCharOrExit

if (Get-Command fzf -ErrorAction Ignore) {
    if (Get-Module -ListAvailable PSFzf) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
    }
}

# --- tools -------------------------------------------------------------------
if (Get-Command fnm -ErrorAction Ignore) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
if (Get-Command zoxide -ErrorAction Ignore) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# --- project locations (as in zsh/.zshenv) -----------------------------------
$env:CODE_DIR = Join-Path $HOME 'Code'
$env:MAS_DIR = Join-Path $env:CODE_DIR 'Projects\MyAnimeSeason'

function mas {
    Push-Location $env:MAS_DIR
    try { uv run mas @args } finally { Pop-Location }
}

# --- prompt (last, so it wraps everything above) -----------------------------
if (Get-Command starship -ErrorAction Ignore) {
    $env:STARSHIP_CONFIG = Join-Path $PSScriptRoot '..\starship.toml'
    Invoke-Expression (& starship init powershell)
}
