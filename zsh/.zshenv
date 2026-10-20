# De-duplicate PATH/FPATH automatically (keeps first occurrence; avoids
# duplicate entries when this file is re-sourced by nested/child shells).
typeset -U path PATH fpath FPATH

# uv
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# LM Studio CLI (lms)
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"

# bun
[[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"

# pnpm
if [[ -d "$HOME/Library/pnpm" ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
  export PATH="$PNPM_HOME/bin:$PATH"     # typeset -U above drops a repeat
fi

# Antigravity IDE CLI (agy-ide)
[[ -d "$HOME/.antigravity-ide/antigravity-ide/bin" ]] &&
  export PATH="$HOME/.antigravity-ide/antigravity-ide/bin:$PATH"

# Project locations (layout described in $CODE_DIR/README.md)
export CODE_DIR="$HOME/Code"
export MAS_DIR="$CODE_DIR/Projects/MyAnimeSeason"
