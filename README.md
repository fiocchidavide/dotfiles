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
| `zsh`     | Shell entry points | `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.myfunctions`, `~/.hushlogin` (no "Last login" line) |
| `git`     | Git config | `~/.gitconfig` |
| `ssh`     | SSH client config and public key | `~/.ssh/config`, `~/.ssh/id_ed25519.pub` |
| `ghostty` | Ghostty terminal config | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` |
| `vscode`  | VS Code keybindings | `~/Library/Application Support/Code/User/keybindings.json` |
| `claude`  | Global Claude Code instructions and settings | `~/.claude/CLAUDE.md`, `~/.claude/settings.json` |
| `openlogi` | OpenLogi (Logitech mouse remapping); gesture button runs `x shine` | `~/.config/openlogi/config.toml` |
| `linearmouse` | LinearMouse (pointer and scrolling) | `~/.config/linearmouse/linearmouse.json` |

Not stow packages: `plugins/` (Claude Code plugins, read in place through `.claude-plugin/marketplace.json`) and `alfred/`.

**`alfred/`** is Alfred's preferences folder (`Alfred.alfredpreferences`:
features, appearance, workflows, snippets). Alfred replaces its files on save
instead of writing through symlinks, so it reads the folder in place instead:
in Alfred Preferences → Advanced → *Set preferences folder…*, choose this
repo's `alfred/`. Do that on a fresh machine too. Alfred keeps the licence,
clipboard history and caches in `~/Library/Application Support/Alfred`, outside
this folder. Workflows can hold API keys in their variables: check them before
committing.

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

## Mice: OpenLogi and LinearMouse

Two mice: a Logitech MX Master 4 and a Razer ProClickM. Natural scrolling is
on system-wide for the trackpad, and both mice are reversed per device. Each
app owns one side, so neither undoes the other:

- **OpenLogi** owns the MX's hardware: buttons, gestures, Action Ring,
  SmartShift (ratchet/free-spin, the `DpiToggle` button switches it) and DPI.
  Every scroll setting stays neutral: no `invert_scroll`, no `smooth_wheel`,
  `smooth_scroll` and `momentum_scrolling` off, both sensitivities at `14` (1×),
  thumb wheel unbound, scroll resolution unset. Any of these makes OpenLogi
  flip the wheel in firmware or swallow the real scroll and post its own,
  which LinearMouse then skips.
  `capture_mouse_events = false`: no HID-level event tap, so OpenLogi never
  sees system input. The bound controls (gesture button, ModeShift, haptic
  panel) are diverted over HID++ and don't need it; the tap is only for
  remapping middle/back/forward, function keys and the wheel features above.
- **LinearMouse** owns all scrolling and pointer acceleration, for both mice.
  *Bypass events from other applications* is on, so OpenLogi's synthetic
  keystrokes and scrolls are left alone. Its Logitech button mappings and
  hardware DPI stay unset (OpenLogi diverts those controls); don't record an
  MX button in its Buttons tab either, which diverts every control while it
  records.

The MX's reverse lives in LinearMouse, not OpenLogi, because IINA undoes
reversal it thinks came from natural scrolling: it flipped OpenLogi's firmware
inversion back, but leaves LinearMouse's alone.

### LinearMouse schemes

Later schemes override earlier ones.

| Scheme | Scrolling |
| ------ | --------- |
| Any mouse | Accelerated (`auto`), pointer acceleration off |
| ProClickM (`0x9b`) | 3 lines per notch, reversed, ⌘+scroll zooms; 10 lines in Preview |
| ProClickM (`0x9a`) | 3 lines per notch, reversed |
| MX Master 4 | 36 px per notch, reversed, high-resolution wheel on; horizontal accelerated, not reversed |
| MX Master 4 in IINA | vertical 1 line per notch, not reversed; horizontal 18 px, reversed (pixel mode divides the thumb wheel by the main wheel's high-resolution multiplier, so small values seek almost nothing) |

Scroll distance modes:

- **Accelerated** (`auto`): macOS's own wheel curve (System Settings → Mouse →
  Scrolling speed). The MX's high-resolution reports are folded back into
  whole notches first, so the fine steps are lost.
- **By pixels** (`"36px"`): a fixed distance per notch everywhere, no curve.
  High-resolution reports pass through as fractions of a notch, so it is the
  mode where the high-resolution wheel pays off. They are not filtered, so
  the ratchet settling into a detent can show as a small backward jump.
  Apps receive trackpad-style precise deltas, which IINA turns into huge
  volume and seek steps (`36` per notch): hence the IINA scheme.
- **By lines** (a number): each app decides how far a line is (small in
  native apps, larger in browsers), and the high-resolution wheel is reduced
  to whole notches.

The *Acceleration* and *Speed* sliders apply after the distance mode, in all
three:

- **Acceleration** multiplies every scroll (`1` = unchanged, `0.5` = half).
  It scales the whole curve; it doesn't change its shape.
- **Speed** adds that many points to every scroll event (`0` = unchanged).
  With the high-resolution wheel that is several events per notch, so keep it
  at `0` there.

LinearMouse reloads its file on change. OpenLogi re-reads `config.toml` only
when asked to (its own app does after saving), so after a hand edit restart
the agent with
`pkill -x openlogi-agent` (its login service starts it again).

## Private settings

No secrets or per-machine settings are versioned (only the git identity in
`.gitconfig` and project paths in `.zshenv`). One file stays git-ignored and
is created per machine:

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
make touchid    # Touch ID for sudo (/etc/pam.d/sudo_local, survives macOS updates)
```

`make install` also installs oh-my-zsh and the third-party plugins
(`fzf-tab`, `zsh-autosuggestions`, `zsh-syntax-highlighting`) into
`$ZSH_CUSTOM/plugins` — these aren't on Homebrew, so without this step a fresh
clone would load none of them.

Still manual (see `Brewfile` comments): `webtorrent-cli` (pnpm) and
`tailscale` (the macOS app ships the CLI).
