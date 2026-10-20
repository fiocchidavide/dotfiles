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
| `vscode`  | VS Code keybindings | `~/Library/Application Support/Code/User/keybindings.json` |
| `claude`  | Global Claude Code instructions | `~/.claude/CLAUDE.md` |

> **Note on tree-folding:** if a directory doesn't exist in `$HOME` yet,
> Stow by default "folds" it into one symlink into this repo (e.g.
> `~/.claude -> claude/.claude`), and every app writing there then writes
> straight into the repo — for `~/.claude` that would mean committing session
> history and credentials. `make link`/`make relink` therefore stow every package with
> `--no-folding` (real directories, one symlink per file), so new packages
> are safe without extra setup. The exception is `FOLD_PACKAGES` in the
> `Makefile` — currently just `x`, which owns all of `~/.config/x`, so new
> functions and its `config.zsh` show up without a relink; `~/.config` is
> created first so only `~/.config/x` folds. As a second safety net,
> `.gitignore` excludes everything under the shared directories except the
> versioned files.

## Private settings

Nothing machine- or person-specific is versioned. One file stays git-ignored
and is created per machine:

**`x/.config/x/config.zsh`**: usernames, 1Password secret references
(`op://…`) and defaults for `x` commands. Start from the versioned
template: `cp x/.config/x/config.zsh.example x/.config/x/config.zsh`.
Commands that need an unset value name it and stop. Secrets themselves
never land on disk: they're read with `op read` when needed.

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
make install    # brew + link + oh-my-zsh
```

Or drive stow directly:

```sh
stow -nv --no-folding zsh   # dry run: preview the symlinks
stow --no-folding zsh       # link (always --no-folding, see the note above)
stow -D zsh                 # unlink
stow -R --no-folding zsh    # relink
mkdir -p ~/.config && stow x   # x is the one package that folds
```

Adding a new package: create `pkg/<path-under-home>/…`, then
`stow --no-folding pkg` (or `make relink`). Per-package `.stow-local-ignore` files list paths stow
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
