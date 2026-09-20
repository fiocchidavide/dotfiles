# dotfiles

Personal macOS dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a **stow package** whose internal structure mirrors
its location under `$HOME`. Stowing a package symlinks its files into `$HOME`,
so the real files stay versioned here.

The repo is position-agnostic: clone it wherever you like (`~/dotfiles`,
`~/Code/dotfiles`, …). Nothing here hardcodes its own location — the
`Makefile` uses `$(CURDIR)` and the `x` dispatcher resolves its own path at
runtime, so both work from any clone location.

## Packages

| Package | Provides | Symlinks |
| ------- | -------- | -------- |
| `x`       | The `x` personal command dispatcher | `~/.config/x` |
| `zsh`     | Shell entry points | `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.myfunctions` |
| `git`     | Git config | `~/.gitconfig` |
| `ghostty` | Ghostty terminal config | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` |

> **Note on `~/.config`:** `~/.config` didn't exist before this repo was first
> stowed, so Stow's tree-folding collapsed the whole directory into one
> symlink (`~/.config -> x/.config`) instead of just `~/.config/x`. Every app
> that writes under `~/.config/*` therefore writes for real into
> `x/.config/*` on disk. Only `x/.config/x` is meant to be tracked here —
> `.gitignore` excludes everything else under `x/.config/`.

## Usage

The `Makefile` wraps the common operations (packages are auto-detected):

```sh
cd path/to/dotfiles
make            # help
make link       # stow every package into $HOME
make relink     # re-stow after adding/removing files
make unlink     # remove all symlinks
make brew       # brew bundle --file=Brewfile
make doctor     # x doctor — check runtime deps
make install    # brew + link
```

Or drive stow directly:

```sh
stow -nv x      # dry run: preview the symlinks
stow x          # link
stow -D x       # unlink
stow -R x       # relink
```

Adding a new package: create `pkg/<path-under-home>/…`, then `stow pkg`
(or `make relink`). Per-package `.stow-local-ignore` files list paths stow
should skip (e.g. `.DS_Store`).

## Dependencies

- `Brewfile` — the Homebrew install manifest (`make brew`).
- Each `x` command declares its runtime binaries with `#@needs` /
  `#@needs-optional` lines; `x doctor` (or `make doctor`) checks them and
  points at the Brewfile for anything missing.

## Fresh machine

```sh
git clone git@github.com:fiocchidavide/dotfiles.git   # clone anywhere
cd dotfiles
make install    # Homebrew + brew bundle + stow everything + oh-my-zsh & plugins
```

`make install` also installs oh-my-zsh and the third-party plugins
(`fzf-tab`, `zsh-autosuggestions`, `zsh-syntax-highlighting`) into
`$ZSH_CUSTOM/plugins` — these aren't on Homebrew, so without this step a fresh
clone would load none of them.

Still manual (see `Brewfile` comments): `webtorrent-cli` (pnpm).
