# dotfiles

Personal macOS dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a **stow package** whose internal structure mirrors
its location under `$HOME`. Stowing a package symlinks its files into `$HOME`,
so the real files stay versioned here.

## Packages

| Package | Provides | Symlinks |
| ------- | -------- | -------- |
| `x`     | The `x` personal command dispatcher | `~/.config/x` |

## Usage

```sh
cd ~/dotfiles

stow -nv x     # dry run: preview the symlinks
stow x         # link package into $HOME

stow -D x      # unlink
stow -R x      # relink (after adding files)
```

Adding a new package: create `pkg/<path-under-home>/…`, then `stow pkg`.

Per-package files named `.stow-local-ignore` list paths stow should skip
(e.g. `.DS_Store`).

## Fresh machine

```sh
git clone git@github.com:fiocchidavide/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow x
```
