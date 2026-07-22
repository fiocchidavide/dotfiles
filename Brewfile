# Homebrew dependency manifest for these dotfiles.
#   Install everything:  brew bundle --file=Brewfile   (or: make brew)
#   Check what's used at runtime, per command:  x doctor
#
# The `x <cmd>` note marks which command needs each package; keep it in sync
# with the `#@needs` lines in x/.config/x/functions/x_*.

# --- x command runtime deps ---
brew "aria2"          # x fastdw   (aria2c)
brew "atool"          # x dw       (aunpack)
brew "mupdf-tools"    # x extrct   (mutool)
brew "m1ddc"          # x shine
brew "openconnect"    # x connect
brew "mpv"            # x watch    (default player)
brew "uv"             # x ocr, mas

# --- dotfiles / shell tooling ---
brew "stow"           # dotfiles symlink management
brew "fnm"            # node version manager (provides node for webtorrent)
brew "zoxide"
brew "fzf"
brew "pure"           # prompt

# --- casks ---
cask "1password-cli"  # x connect  (op)
cask "iina"           # x watch iina

# --- not available via Homebrew (install manually) ---
#   webtorrent-cli   ->  pnpm add -g webtorrent-cli   (x watch)
#   oh-my-zsh        ->  sh -c "$(curl -fsSL https://install.ohmyz.sh/)"
#   zsh plugins      ->  fzf-tab, zsh-syntax-highlighting, zsh-autosuggestions
