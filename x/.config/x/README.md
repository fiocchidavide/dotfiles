# `x` — personal shell command dispatcher

A tiny, lazy-loading subcommand dispatcher for personal zsh helpers.
Type `x` to list commands, `x <name> [args]` to run one, `x <TAB>` to complete,
and `x <name> -h` (or `x help <name> [subcommand]`) for a command's help.

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
  lib/xstream.py           # progress drawing for x gdrive and x rveil
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

## Personal settings

`x.zsh` sources `config.zsh` from this directory if present. It's
git-ignored; `config.zsh.example` lists every key with placeholders. Keep
secrets out of it: store 1Password secret references (`X_*_REF`) and read
them with `op read` at run time.

A command checks the settings it needs with `_x_need_config`, which fails
naming any key that's empty or still an `<placeholder>`:

```zsh
_x_need_config X_FOO_USER X_FOO_PASSWORD_REF || return
password=$(op read "$X_FOO_PASSWORD_REF")
```

`_x_ask_config VAR "question" [default]` instead asks for a missing value on
the terminal and appends it to `config.zsh`, so it's asked only once.

## Adding a command

`x new <name>` scaffolds all of this.

1. Create `functions/x_<name>`. Its contents are the command **body** — no
   `x_<name>() { … }` wrapper (zsh autoload convention).
2. Make the first `## ` line its one-line description; it feeds `x` help and
   tab-completion. No registry to maintain.
3. Write a `# Usage:` comment block. The Usage line itself gives the
   command's shape (`# Usage: x watch [player] [--ram[=GiB]] <url>`). Below
   it, after a `#` line: one `#   x <name> …` line per form or subcommand (3
   spaces in), then 2+ spaces and what it does, or the description on the
   more indented lines below; option lines (`#   -k keyid    …`) under an
   `# Options:` heading; then prose. It ends at the first blank line.
   It's for using the command: what it does, what it reads, what to expect.
   How it works (pipelines, why a workaround exists) goes in comments after
   that blank line, where help never shows it.
4. Optional: declare external dependencies with `#@needs <bin>…` (required)
   and/or `#@needs-optional <bin>…` lines. `x doctor` checks them. Add the
   matching Homebrew formula/cask to `../../../Brewfile`.
5. Complete what follows the command and its subcommands: add `<name>` to the
   `_files` case in `_x` (inside `x.zsh`) if it takes a path, or add
   `functions/_x_<name>_complete` (see `_x_rveil_complete`).

Example — `functions/x_hello`:

```zsh
## say hello to someone
#@needs cowsay
# Usage: x hello [name]
#
# Greets name (default: world).

cowsay "Hi, ${1:-world}!"
```

Then `x hello`, `x` (lists it), `x he<TAB>` (completes it), `x hello -h`.

### The Usage block is the interface

Plain words right after `x <name>` in a synopsis are subcommands, and
`off|stop` names one together with its aliases:

```zsh
# Usage: x rveil <command> …
#
#   x rveil keys                list master keys
#   x rveil keys new            create one
#   x rveil rm <match>…
#                               delete archives
```

`x rveil -h` renders it like the `x` command list: the shape first, then the
forms in aligned columns with their descriptions in grey, then the prose.

From that block, `x` itself does what every command would otherwise do by
hand, the same way for all of them:

- `x rveil -h`, `--help`, `x rveil help` and `x help rveil` print the block;
  `x rveil keys --help` prints only the `x rveil keys …` lines. On stdout,
  status 0.
- A missing subcommand (`x ramdisk`) prints the block on stderr, status 1,
  unless a synopsis shows the bare form (`x rveil keys`). An unknown one
  (`x ramdisk nope`) is an error before the command runs, so nothing is asked
  for or started.
- `x rveil <TAB>` and `x rveil keys <TAB>` complete the subcommands, with
  their descriptions. What follows them is up to the command's hook.

So a command handles none of that. On misuse it shows its help with
`_x_help <name> [subcommand…]; return`, and a command parsing `-h` among
other options (`x watch -i -h`) uses `_x_help -o <name>`.

`.github/scripts/discover.zsh` (in CI) holds every command to this: for the
command and each subcommand its block names, help works all four ways and
runs nothing; missing and unknown subcommands fail cleanly; completion offers
the subcommands, every documented option and something for each argument;
every option the code parses with `zparseopts` is documented; and the
dispatch `case` handles exactly the documented subcommands and aliases. A
subcommand's handler is `_x_<name>_<sub>` (`_x_rveil_keys_new`), which is how
the check finds its options.

### Output helpers: one design language

`x.zsh` defines how x looks, and every command speaks through it: one Nerd
Font icon and one colour per role, kept in `X_ICONS` and `X_COLORS`. Don't
`echo` emoji or write escape codes in a command. Use a role, and restyle all of
x by editing those two tables.

Status lines go to stderr, so stdout stays clean for data; reports a command
was asked for (lists, status, `x doctor`) go to stdout. Colour and animation
appear only on a terminal. `NO_COLOR` turns colour off, and `X_QUIET=1` (map
your `-q` to it) silences everything but warnings and errors.

| Helper | Use |
|---|---|
| `_x_step` / `_x_info` | doing something (bold) / a detail or hint (dim) |
| `_x_ok` / `_x_warn` / `_x_err` | it worked / worth knowing / it failed |
| `_x_help [-o] foo [sub…]` | the command's Usage block (a subcommand's lines only); on stderr with status 1, or stdout with `-o` when `-h`/`--help` asked for it (and status 0) |
| `_x_heading`, `_x_row name text` | report heading, aligned name/description rows |
| `_x_item on\|half\|off\|ok\|err text` | report line led by a state icon (x serve, x connect) |
| `_x_mark role text` | inline mark, several per line (x doctor) |
| `_x_paint style text`, `_x_icon role` | inline styled text or icon, for composing |
| `_x_spin [-t] "label" cmd…` | spinner with elapsed time while cmd runs, then a success or error line (`-t`: no line on success); cmd's stdout passes through |
| `_x_ask var "prompt" [-s]`, `_x_ask_yn "question"` | read from the terminal (stdin without one) |
| `_x_bytes n`, `_x_elapsed t0` | `1.2 GiB`, `4.2s` / `3:07` |

## Google Drive: `x gdrive`

`x gdrive` reaches Google Drive through rclone remotes defined in 1Password:
`login`, `up`, `down`, `ls`, `link`, … Encrypted backups go through
[`x rveil`](#x-rveil-rveil-the-x-way); rveil's README covers its design,
archive format and recovery with stock tools.

`x vault`, the backup framework that came before rveil, is retired, and so
are `x seal`, `x unseal` and `x kdf`, the tools it was built on. Their last
versions are in commit `5f29819`, with the README describing their archive
format and recovery without them:
`git show 5f29819:x/.config/x/README.md`, `git show 5f29819:x/.config/x/functions/x_unseal`.

### Drive remotes

Each rclone remote is one item in the 1Password vault `X_GDRIVE_OP_VAULT`
(default `x-gdrive`). The item title is the remote name, and the fields are
`client id`, `client secret` (a Google OAuth client of type Desktop app),
`scope` and `used for`.

| Remote | Scope | Used by |
|---|---|---|
| `rveil` | `drive.file` | `x rveil` (rveil's default remote): its token reaches only files that client created |
| `drive` | `drive` | `x gdrive` by default (`X_GDRIVE_REMOTE`); `-r <remote>` picks another |

- `x gdrive remotes` lists the items and whether each is connected, needs
  filling in, or changed since the last login.
- `x gdrive client new <name> --scope <s>` scaffolds a new item.
- `x gdrive -r <name> login` creates or updates the rclone remote from its
  item and authorises it in the browser. Change the scope or client in
  1Password, then log in again to apply it.

`drive.file` access is per OAuth *client*, so with separate clients one
remote's token can't see what another uploads. The general remote (full
`drive` scope) still sees everything, the encrypted archives included. A
client's Cloud project needs the Drive API enabled, its scope listed under
Data Access, and the app published ("In production"), or logins expire
after 7 days.

## `x rveil`: rveil, the x way

[rveil](https://github.com/fiocchidavide/rveil) keeps encrypted, padded
archives on an rclone remote, with its keys in 1Password: the successor of
`x vault`, as one Go program with a plain, rclone-like command line. `x rveil`
puts x's look and conveniences on it:

- **What rveil is doing, as it does it.** rveil runs with
  `-vv --use-json-log`, and `xstream.py rveillog` draws its log: a spinner
  with each step (unlocking keys in 1Password, reading the index, checking
  the remote's hash…), the `x gdrive` progress bar for transfers, and a
  line in x's icons and colours for each outcome, notice and error.
- **Originals.** `put` remembers where each archive came from (per
  machine, under `$XDG_STATE_HOME/x/rveil`). Once `push` (or `put --direct`)
  has the archive verified on the remote, it offers to delete the original,
  unless it changed after sealing.
- **Questions the x way** before `rm` and `rekey`, then rveil runs with `-y`.
- **Completion** of every archive by name, with its date, size and id
  beside it (from a cache refreshed whenever `x rveil` reads the index), and
  of staged archives for `push` (from rveil, offline). A completed name
  picks exactly that archive, even if other names contain it.

Install rveil with `go install davidefiocchi.com/rveil@latest`. Settings are
optional (`X_RVEIL_*` in `config.zsh`); rveil's defaults are the 1Password
vault `rveil` and the remote `rveil:rveil`. For Google Drive, give it its own
OAuth client: an item `rveil` in `X_GDRIVE_OP_VAULT` (scope `drive.file`),
then `x gdrive -r rveil login`.

## `x colab`: a Colab runtime for the repo you're in

`x colab up`, run in a clone of a GitHub repo, starts a Colab runtime named
after the repo, clones the repo there and attaches to a tmux session in it.
Each step is also its own subcommand (`token`, `new`, `clone`, `tmux`,
`stop`), on top of Google's [`colab` CLI](https://pypi.org/project/google-colab-cli/).

The runtime gets as little as it can work with:

- **A token for this one repo.** `x colab token` opens GitHub's new-token
  page filled in (owner, Contents read, or write with `-w`, 7 days); GitHub
  can't prefill the repo, so pick it there. The pasted token is checked
  against the repo and kept in 1Password (`X_COLAB_OP_VAULT`, item
  `<owner>/<repo>`) until it expires, so the next runtime reuses it. GitHub
  has no API to create these tokens, hence the page.
- **No SSH agent.** ssh reaches the runtime through `colab ssh --proxy-mode`,
  given on the command line, with agent forwarding off: the runtime can't
  use your keys. ~/.ssh/config isn't touched.

Install the CLI with `uv tool install google-colab-cli`. It registers
`~/.ssh/id_ed25519.pub` with the runtime, so that file must hold the public
half of a key your SSH agent has.

## Installing

In the dotfiles repo this directory is the `x` stow package. It is the one
package that folds: `make link` creates `~/.config` and then symlinks
`~/.config/x` to it, so new commands and `config.zsh` show up without a
relink. See the repo's README.
