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
| `paseo`   | Paseo daemon config (rendered, see below) | `~/.paseo/config.json` |
| `vscode`  | VS Code keybindings | `~/Library/Application Support/Code/User/keybindings.json` |

> **Note on `~/.config` and `~/.paseo`:** only `~/.config/x` and
> `~/.paseo/config.json` are meant to be symlinked here.
> If `~/.config` doesn't exist yet when stowing, Stow's tree-folding will
> collapse the whole directory into one symlink (`~/.config -> x/.config`)
> instead of just `~/.config/x`, and every other app then writes its real
> config straight into this repo — for `~/.paseo` that would mean committing
> the daemon keypair, client id and logs. `make link`/`make relink` guard
> against this by pre-creating both as real directories before stowing. As a
> second safety net, `.gitignore` excludes everything under `x/.config/` and
> `paseo/.paseo/` except `x/.config/x` and `paseo/.paseo/config.json.tmpl`.
> The same applies to `~/Library/Application Support/Code/User` (VS Code's
> caches and workspace storage), which is pre-created and git-ignored except
> for `keybindings.json`.

## Private settings

Nothing machine- or person-specific is versioned. Two files stay git-ignored
and are created per machine:

- **`x/.config/x/config.zsh`**: usernames, 1Password secret references
  (`op://…`) and defaults for `x` commands. Start from the versioned
  template: `cp x/.config/x/config.zsh.example x/.config/x/config.zsh`.
  Commands that need an unset value name it and stop. Secrets themselves
  never land on disk: they're read with `op read` when needed.
- **`paseo/.paseo/config.json`**: rendered by `make paseo-config` (run by
  `make link`/`relink`) from the versioned `config.json.tmpl`, adding this
  node's Tailscale hostname to the daemon's allowed hostnames. Edit the
  template, not the rendered file.

## Usage

The `Makefile` wraps the common operations (packages are auto-detected):

```sh
cd path/to/dotfiles
make            # help
make link       # render paseo config, then stow every package into $HOME
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
cp x/.config/x/config.zsh.example x/.config/x/config.zsh   # then fill it in
```

`make install` also installs oh-my-zsh and the third-party plugins
(`fzf-tab`, `zsh-autosuggestions`, `zsh-syntax-highlighting`) into
`$ZSH_CUSTOM/plugins` — these aren't on Homebrew, so without this step a fresh
clone would load none of them.

Still manual (see `Brewfile` comments): `webtorrent-cli` (pnpm).
