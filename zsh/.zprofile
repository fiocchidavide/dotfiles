# Homebrew (only once it's installed: make install runs before it exists)
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# /etc/zprofile's path_helper moved ~/.zshenv's per-user folders behind the
# system ones; put them back in front (typeset -U drops the later copies).
path=($_dotfiles_user_path $path)

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
