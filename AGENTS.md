# Working on this repo

Personal macOS dotfiles managed with GNU Stow, plus `x`, a zsh command
dispatcher with its own conventions. `README.md` (repo) and
`x/.config/x/README.md` (x) are the user-facing docs; this file is what to
know before changing anything.

## Layout

| Path | What it is |
| ---- | ---------- |
| `<pkg>/…` | A stow package: every top-level directory, mirroring `$HOME` (`zsh/.zshrc` → `~/.zshrc`) |
| `x/.config/x/` | The `x` dispatcher (`x.zsh`), its commands (`functions/x_<name>`), completion hooks (`functions/_x_<name>_complete`), `lib/xstream.py` |
| `zsh/` | `.zshenv`, `.zprofile`, `.zshrc`, `.myfunctions` (sources `x.zsh`) |
| `claude/.claude/CLAUDE.md` | The user's **global** Claude Code instructions, stowed to `~/.claude/CLAUDE.md`. Not about this repo; edit only when asked |
| `Brewfile` | Homebrew deps; the "install manually" comments list what brew can't provide |
| `Makefile` | `make link / relink / unlink / brew / install / doctor`; packages are auto-detected |
| `.github/workflows/lint.yml`, `.github/scripts/` | CI and its test scripts |

## Stow

- Packages are stowed with `--no-folding`, so `$HOME` gets real directories
  with one symlink per file. Otherwise apps writing into e.g. `~/.claude`
  would write into the repo. Only `x` folds (`FOLD_PACKAGES`), so
  `~/.config/x` is a single symlink.
- `.gitignore` is a second safety net: under shared directories
  (`claude/.claude`, `vscode/…/User`, `ghostty/…`, `x/.config`) only the
  versioned files are un-ignored. A new file there needs a `!` exception.
- `x/.config/x/config.zsh` is per machine and git-ignored; keys are
  documented in `config.zsh.example`. Never commit secrets: values are
  1Password references (`op://…`) read with `op read` when needed.
- The repo is position-agnostic: don't hardcode its path (`$(CURDIR)` in
  make, `$X_DIR` in x).

## zsh startup

- `.zshenv` runs for every zsh, including `zsh -c` children. It must stay
  cheap and must only **prepend what's missing** to PATH
  (`path=(${new:|path} $path)`), so a child of a venv or fnm shell keeps
  their order.
- `.zprofile` (login shells) puts `$_dotfiles_user_path` back in front after
  macOS's `path_helper` reorders PATH.
- `.zshrc`: oh-my-zsh (plugins from `make omz`), Pure prompt,
  `.myfunctions`, then fnm and zoxide when installed.

## x commands

Read the header of `x/.config/x/x.zsh` and "Adding a command" in its README
first. The essentials:

- A command is `functions/x_<name>`, a **function body** (zsh autoload). Its
  first `## ` line is its one-line description. `#@needs` /
  `#@needs-optional` lines declare binaries for `x doctor` (and the Brewfile).
- Bodies start with `emulate -L zsh`; add `setopt extended_glob` etc. as needed.
- **The `# Usage:` block is the interface.** `x` derives everything about
  discoverability from it, so commands implement none of it:
  `-h`/`--help`/`help`, `x help <cmd> [sub]`, missing and unknown subcommand
  errors, subcommand completion, and how help is rendered. Its format:

  ```zsh
  # Usage: x rveil <command> …              <- the shape of the command
  #
  #   x rveil keys                list master keys
  #   x rveil keys new            create one
  #   x rveil rm <match>…
  #                               delete archives   <- description continued
  #   x serve off|stop [target]   stop sharing      <- a subcommand + its aliases
  #
  # Options:
  #   -k keyid    master key to derive from
  #
  # Prose about using the command.

  # Implementation notes go here, after the blank line: never shown as help.
  ```

  - Synopsis lines are 3 spaces in, and the description follows after
    2+ spaces. Option lines (`-x …`) are also 3 spaces in. Continuation lines
    are indented further.
  - Plain words right after `x <name>` are parsed as **subcommands**. In
    examples, use placeholders (`x doctor <command>`), never literal values
    (`x doctor vault`).
  - The block is for using the command. How it works goes in comments after
    the blank line that ends it.
- On misuse a command shows its help with `_x_help <name> [sub…]; return`
  (stderr, status 1). Use `_x_help -o <name>` only where it parses `-h` among
  other options (`x watch -i -h`). Never hand-write usage strings
  (`_x_usage` is for `x` itself).
- Subcommand handlers are named `_x_<cmd>_<sub>[_<sub>]` (`_x_rveil_keys_new`).
  CI reads their `zparseopts` by that name, so keep helpers off that pattern
  (`_x_gdrive_client_item`, not `_x_gdrive_client`).
- Dispatch with a top-level `case` whose labels are exactly the documented
  subcommands and aliases (`off|stop|down|d)`), plus `*) _x_help <cmd> ;;`.
- **Completion:** `_x` completes subcommand words from the Usage block. A hook
  `_x_<cmd>_complete` covers only what follows them: options, files, values.
  - Before `_arguments`, drop the leading words
    (`shift words; (( CURRENT-- ))`; `shift 2 words` after a subcommand), or
    it takes `x` for the command.
  - Test positions with `(( CURRENT == 4 ))`. Inside `[[ ]]`, `CURRENT == 4`
    compares the literal string `CURRENT`.
  - Commands that only take a path can go in the `_files` case at the end of
    `_x` instead.
- **Output** goes through the helpers in `x.zsh` (`_x_step/_x_info/_x_ok/
  _x_warn/_x_err`, `_x_heading/_x_row/_x_item`, `_x_spin`).
  - Status lines go to stderr; data and requested reports go to stdout.
  - No raw emoji or escape codes: icons and colours live in `X_ICONS` and
    `X_COLORS`.
  - Honour `NO_COLOR` and `X_QUIET` (map `-q` to `X_QUIET=1`).
- **Settings:** `_x_need_config VAR…` stops with a pointer to `config.zsh`;
  `_x_ask_config VAR "question" default` asks once and saves the answer.
  Ask only on paths that need the value, never before help.
- **Secrets** reach programs on stdin or a pipe fd, never argv or the
  environment. Options that take one accept only `-` (stdin).
- **Prompts:** use `_x_ask` / `_x_ask_yn`. They read and prompt on
  `/dev/tty`, so they work when stdout or stderr is redirected.
- With `pipe_fail`, a `producer | head -c` pipe returns status 141
  (SIGPIPE), so wrap such pipes in a helper with
  `setopt local_options no_pipe_fail`.
- **Python** (`lib/xstream.py`) runs as
  `uv run --quiet --no-project python -I …`. Use uv for anything Python.
- `x new <name>` scaffolds a compliant command. After editing, run `x reload`.

## Checks (all run in CI on every push)

```sh
for f in x/.config/x/x.zsh x/.config/x/functions/* x/.config/x/config.zsh.example zsh/.z* zsh/.myfunctions .github/scripts/*.zsh; do zsh -n "$f"; done
zsh -f .github/scripts/discover.zsh     # every command/subcommand: help, errors, completion, docs vs code
zsh -f .github/scripts/units.zsh        # pure helpers: formatting, x rveil matching and log drawing (needs uv, jq)
make -n help
```

`discover.zsh` checks every command and every subcommand its Usage block
names:
- all help forms print the same text to stdout and run nothing (tools are
  stubbed);
- missing and unknown subcommands fail cleanly;
- completion offers the subcommands, every documented option and something
  for each argument;
- every `zparseopts` option is documented;
- the dispatch `case` matches the documented subcommands and aliases.

When it fails, fix the command or its Usage block, not the check.

To test real completion, drive an interactive `zsh -f -i` through `zpty`
with `compinit`, wrapping `compadd` to log what it offers.

## Commits

- One commit per piece of work. The subject is a one-line summary of the
  changes, joined with commas (see `git log`), and the body says what changed
  and why.
- No AI attribution anywhere: no co-author trailers, "generated with"
  footers, or notes in code or docs.
- Run the checks above before committing. Don't push unless asked.
