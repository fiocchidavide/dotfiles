# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# No oh-my-zsh theme: Pure (below) draws the prompt.
ZSH_THEME=""

# NOTE: zsh-syntax-highlighting must be LAST (after zsh-autosuggestions).
plugins=(fzf-tab git zsh-autosuggestions zsh-syntax-highlighting)

# Homebrew completions are already on fpath for compinit: `brew shellenv` in
# ~/.zprofile adds $HOMEBREW_PREFIX/share/zsh/site-functions.
source $ZSH/oh-my-zsh.sh

# pure zsh template
# oh-my-zsh overrides the prompt so Pure must be activated after source $ZSH/oh-my-zsh.sh
autoload -U promptinit; promptinit
prompt pure

source ~/.myfunctions

# fnm
eval "$(fnm env --use-on-cd --shell zsh)"

# zoxide
eval "$(zoxide init zsh)"
