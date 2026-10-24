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
brew "rclone"         # x serve webdav, x gdrive, x rveil
brew "uv"             # x ocr, x datalab, x gdrive, x rveil, mas
brew "jq"             # x gdrive, x serve, x rveil  (macOS 15+ also ships one)

# --- dotfiles / shell tooling ---
brew "stow"           # dotfiles symlink management
brew "gh"             # git credential helper for github.com (.gitconfig)
brew "fnm"            # node version manager (provides node for webtorrent)
brew "pnpm"           # installs webtorrent-cli (see below)
brew "zoxide"
brew "fzf"            # also x watch -i (optional)
brew "pure"           # prompt

# --- casks ---
cask "1password-cli"  # x connect, x datalab, x gdrive, x serve, x rveil  (op)
cask "iina"           # x watch iina

# --- not available via Homebrew (install manually) ---
#   webtorrent-cli   ->  pnpm add -g webtorrent-cli   (x watch)
#   tailscale        ->  the macOS app ships the CLI   (x serve)
#   rveil            ->  go install davidefiocchi.com/rveil@latest   (x rveil)
#   oh-my-zsh and its plugins (fzf-tab, zsh-syntax-highlighting,
#   zsh-autosuggestions) -> make omz, which keeps this repo's ~/.zshrc
