# De-duplicate PATH/FPATH automatically (keeps first occurrence; avoids
# duplicate entries when this file is re-sourced by nested/child shells).
typeset -U path PATH fpath FPATH

# Prepending only what's missing (${a:|path}) keeps an inherited order: a
# child shell (zsh -c) of an activated venv or an fnm shell must not put these
# back in front of .venv/bin or fnm's node.

# Homebrew, for shells that never read ~/.zprofile (zsh -c from a GUI app);
# login shells get the full `brew shellenv` there.
if [[ -d /opt/homebrew/bin ]]; then
  typeset -a _dotfiles_brew_path=(/opt/homebrew/bin /opt/homebrew/sbin)
  path=(${_dotfiles_brew_path:|path} $path)
  unset _dotfiles_brew_path
fi

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
# go install
[[ -d "$HOME/go/bin" ]] && _dotfiles_user_path+=("$HOME/go/bin")
path=(${_dotfiles_user_path:|path} $path)

# LM Studio CLI (lms), last on purpose
[[ -d "$HOME/.lmstudio/bin" ]] && path+=("$HOME/.lmstudio/bin")

# Project locations (layout described in $CODE_DIR/README.md)
export CODE_DIR="$HOME/Code"
export MAS_DIR="$CODE_DIR/Projects/MyAnimeSeason"
