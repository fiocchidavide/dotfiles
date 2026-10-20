# De-duplicate PATH/FPATH automatically (keeps first occurrence; avoids
# duplicate entries when this file is re-sourced by nested/child shells).
typeset -U path PATH fpath FPATH

# Homebrew, for shells that never read ~/.zprofile (zsh -c from a GUI app);
# login shells get the full `brew shellenv` there.
[[ -d /opt/homebrew/bin ]] && path=(/opt/homebrew/bin /opt/homebrew/sbin $path)

# Per-user tool folders, ahead of everything else. In login shells macOS's
# /etc/zprofile (path_helper) moves them behind the system folders, so
# ~/.zprofile puts $_dotfiles_user_path back in front.
typeset -ga _dotfiles_user_path=()
# Antigravity IDE CLI (agy-ide)
[[ -d "$HOME/.antigravity-ide/antigravity-ide/bin" ]] &&
  _dotfiles_user_path+=("$HOME/.antigravity-ide/antigravity-ide/bin")
# pnpm
if [[ -d "$HOME/Library/pnpm" ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
  _dotfiles_user_path+=("$PNPM_HOME/bin")
fi
# bun
[[ -d "$HOME/.bun/bin" ]] && _dotfiles_user_path+=("$HOME/.bun/bin")
# uv
[[ -d "$HOME/.local/bin" ]] && _dotfiles_user_path+=("$HOME/.local/bin")
path=($_dotfiles_user_path $path)

# LM Studio CLI (lms), last on purpose
[[ -d "$HOME/.lmstudio/bin" ]] && path+=("$HOME/.lmstudio/bin")

# Project locations (layout described in $CODE_DIR/README.md)
export CODE_DIR="$HOME/Code"
export MAS_DIR="$CODE_DIR/Projects/MyAnimeSeason"
