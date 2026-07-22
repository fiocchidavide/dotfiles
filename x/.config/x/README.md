# `x` — personal shell command dispatcher

A tiny, lazy-loading subcommand dispatcher for personal zsh helpers.
Type `x` to list commands, `x <name> [args]` to run one, `x <TAB>` to complete.

Self-management (built-in commands):

- `x new <name>`  — scaffold a new command file and open it in `$EDITOR`
- `x edit <name>` — edit an existing command, then reload
- `x reload`      — refresh all definitions after editing files by hand
- `x doctor`      — check each command's declared dependencies

## Layout

```
~/.config/x/
  x.zsh                    # dispatcher, help, completion (source this from your shell)
  functions/
    x_<name>               # one command per file, autoloaded on first use
    _x_<name>_complete     # optional per-command completion hook
```

`x.zsh` finds its own directory (symlink-resolved, so it works when stowed),
adds `functions/` to `$fpath`, and marks every `x_*` file for `autoload`. A
command's body is only compiled the first time you actually run it.

## Wiring it up

Add to `.zshrc` (or, as here, source it from `~/.myfunctions`):

```zsh
source ~/.config/x/x.zsh
```

Completion needs `compinit` to have run (the standard interactive setup).

## Adding a command

1. Create `functions/x_<name>`. Its contents are the command **body** — no
   `x_<name>() { … }` wrapper (zsh autoload convention).
2. Make the first `## ` line its one-line description; it feeds `x` help and
   tab-completion. No registry to maintain.
3. Optional: declare external dependencies with `#@needs <bin>…` (required)
   and/or `#@needs-optional <bin>…` lines. `x doctor` checks them. Add the
   matching Homebrew formula/cask to `../../../Brewfile`.
4. Optional: add `functions/x_<name>` to the `_files` case in `_x` (inside
   `x.zsh`) if it takes a path argument, or add `functions/_x_<name>_complete`
   for richer sub-argument completion (see `_x_ramdisk_complete`).

Example — `functions/x_hello`:

```zsh
## say hello to someone
#@needs cowsay
cowsay "Hi, ${1:-world}!"
```

Then `x hello`, `x` (lists it), `x he<TAB>` (completes it).

## Backup with GNU stow

This directory is self-contained and path-independent, so it stows cleanly.
Move it into a dotfiles repo mirroring `$HOME`:

```
~/dotfiles/               # git repo
  x/                      # stow package
    .config/x/            # <- this directory
```

Then:

```sh
cd ~/dotfiles
stow x            # symlinks ~/.config/x -> ~/dotfiles/x/.config/x
```

Because `x.zsh` resolves its own real path, autoloading keeps working through
the symlink.
