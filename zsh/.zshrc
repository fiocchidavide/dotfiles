# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# No oh-my-zsh theme: Pure (below) draws the prompt.
ZSH_THEME=""

# NOTE: zsh-syntax-highlighting must be LAST (after zsh-autosuggestions).
plugins=(fzf-tab git zsh-autosuggestions zsh-syntax-highlighting)

# Homebrew completions are already on fpath for compinit: `brew shellenv` in
# ~/.zprofile adds $HOMEBREW_PREFIX/share/zsh/site-functions.
# Guarded like fnm and zoxide below: a fresh machine lacks it until make omz.
[[ -r $ZSH/oh-my-zsh.sh ]] && source $ZSH/oh-my-zsh.sh

# pure zsh template
# oh-my-zsh overrides the prompt so Pure must be activated after source $ZSH/oh-my-zsh.sh
autoload -U promptinit; promptinit
(( ${prompt_themes[(Ie)pure]} )) && prompt pure

source ~/.myfunctions

# fnm and zoxide, where installed (a fresh machine before make brew lacks them)
(( $+commands[fnm] )) && eval "$(fnm env --use-on-cd --shell zsh)"
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# Echo back on (~/.zshenv turned it off while the shell started), once, after
# every other precmd hook (Pure's, fnm's) so nothing echoes before the prompt
_dotfiles_echo_on() {
  [[ -t 0 ]] && stty echo
  precmd_functions=(${precmd_functions:#_dotfiles_echo_on})
  unfunction _dotfiles_echo_on
}
precmd_functions+=(_dotfiles_echo_on)

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/davide/.lmstudio/bin"
# End of LM Studio CLI section

