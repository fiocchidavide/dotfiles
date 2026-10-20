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
  lib/xstream.py           # HKDF, hashing and padding for x kdf / seal / vault
  share/open.sh            # public one-shot decrypt script for x vault share
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

### Output helpers

`x.zsh` provides these for every command. Status goes to stderr, so stdout
stays clean for data. Colour and animation appear only on a terminal.
`NO_COLOR` turns colour off, and `X_QUIET=1` (map your `-q` to it) silences
everything but warnings and errors.

| Helper | Use |
|---|---|
| `_x_step` / `_x_info` / `_x_ok` / `_x_warn` / `_x_err` | heading, dim detail, success, warning, error lines, with Nerd Font icons from `X_ICONS` |
| `_x_spin [-t] "label" cmd…` | spinner with elapsed time while cmd runs, then a success or error line (`-t`: no line on success); cmd's stdout passes through |
| `… \| _x_pv -s bytes -N label \| …` | progress bar for a byte stream (`xstream.py meter`, the same bar as `x gdrive` transfers), a plain pass-through otherwise |
| `_x_ask var "prompt" [-s]`, `_x_ask_yn "question"` | read from the terminal (stdin without one) |
| `_x_bytes n`, `_x_elapsed t0` | `1.2 GiB`, `4.2s` / `3:07` |

## Encrypted backups: `x kdf`, `x seal`, `x unseal`, `x gdrive`, `x vault`

Back up to Google Drive without Google being able to read content, names or
exact sizes. Each layer works on its own:

| Command | Role |
|---|---|
| `x kdf` | per-archive passphrase from a master key (HKDF-SHA256) |
| `x seal` / `x unseal` | file or folder ⇄ one `.age` archive |
| `x gdrive` | Google Drive via rclone remotes defined in 1Password: `login`, `up`, `down`, `ls`, `link`, … |
| `x vault` | the backup framework: keys, index, staging, `put`/`push`/`get`/`rm`, `rekey`, `share` |

First run: `x gdrive -r vault login`, then `x vault init`. Daily use:
`x vault put ~/Photos/2019`, then `x vault push`. With several archives
staged, `push` opens an fzf picker (Tab marks several). `--all` skips the
picker, patterns pick by path (`x vault push Photos`), and `-n` lists
without uploading. Or
`x vault put --direct /Volumes/Ext/Big` for data that doesn't fit locally.

### Drive remotes

Each rclone remote is one item in the 1Password vault `X_GDRIVE_OP_VAULT`
(default `x-gdrive`). The item title is the remote name, and the fields are
`client id`, `client secret` (a Google OAuth client of type Desktop app),
`scope` and `used for`.

| Remote | Scope | Used by |
|---|---|---|
| `vault` | `drive.file` | `x vault` only (hardcoded): its token reaches only files that client created |
| `drive` | `drive` | `x gdrive` by default (`X_GDRIVE_REMOTE`); `-r <remote>` picks another |

- `x gdrive remotes` lists the items and whether each is connected, needs
  filling in, or changed since the last login.
- `x gdrive client new <name> --scope <s>` scaffolds a new item.
- `x gdrive -r <name> login` creates or updates the rclone remote from its
  item and authorises it in the browser. Change the scope or client in
  1Password, then log in again to apply it.

`drive.file` access is per OAuth *client*, so with separate clients the
vault's token can't see what the general remote uploads. The general remote
(full `drive` scope) still sees everything, the vault's encrypted files
included. A client's Cloud project needs the Drive API enabled, its
scope listed under Data Access, and the app published ("In production"), or
logins expire after 7 days.

### Cryptography

- **Master keys**: 32 random bytes each, one item per key in a dedicated
  1Password vault (`X_VAULT_OP_VAULT`, default `x-vault`). Item title = key
  id (6 base32 characters); fields `key`, `created`, `status`
  (`active`/`retired`/`compromised`). The item `settings` has `current`. Keys
  reach 1Password through a JSON template on stdin, never argv.
- **Per-archive passphrase**: `base64url(HKDF-SHA256(ikm = master key,
  salt = "x-vault/v1", info = "file" 0x00 keyid 0x00 name, 32 bytes))`.
  `name` is the archive's file name without `.age`
  (`<keyid>.<26 random base32>`), so every archive has an independent key,
  and handing one out (`x vault key`) exposes nothing else. `x kdf --selftest`
  checks the RFC 5869 vectors.
- **Archive**: `tar | zstd -9 --long=27 | Padmé padding | age` in scrypt
  passphrase mode (`age -j batchpass`, the passphrase on a pipe fd). age
  is ChaCha20-Poly1305 in an authenticated stream, so tampering and
  truncation fail loudly. Everything is symmetric, so it holds up against
  "harvest now, decrypt later" with quantum computers.
- **Padding**: Padmé rounds the compressed stream up to a size bucket (≤ 12%
  overhead), using zstd *skippable frames*, which `zstd -d` ignores by
  itself. The `.age` size reveals only the bucket. `--no-pad` turns it off.
- **Index**: `<keyid>.index.age` on Drive, sealed like any archive, maps
  archive names to original paths, sizes, dates and hashes (tar stream,
  inner stream, ciphertext).
- **Verification**: an upload counts only when Drive's SHA-256 equals the
  ciphertext hash computed while sealing. Before an original is deleted, the
  copy on Drive is streamed back, decrypted and compared with the tar hash.
  The original is kept if it changed after sealing.
- **Rekey** replaces only the outer age layer, Drive → pipe → Drive (no
  decompression, nothing on disk). It checks the decrypted stream against the
  recorded hash, then switches the index, and only then deletes the old
  archive.

### Recovery without these tools

You need the master key (1Password) and the archive's name.

```sh
id=k7f3a2 name=k7f3a2.abcdefghijklmnopqrstuvwxyz
info=$(printf 'file\0%s\0%s' $id $name | xxd -p | tr -d '\n')
m=$(printf '%s' '<base64url master key>' | tr '_-' '/+')
while [ $(( ${#m} % 4 )) -ne 0 ]; do m="$m="; done   # restore base64 padding
key=$(printf '%s' "$m" | base64 -d | xxd -p | tr -d '\n')
openssl kdf -keylen 32 -kdfopt digest:SHA256 -kdfopt hexkey:$key \
  -kdfopt salt:x-vault/v1 -kdfopt hexinfo:$info -binary HKDF |
  base64 | tr '+/' '-_' | tr -d '='          # -> the passphrase
age -d $name.age | zstd -d | tar x           # age prompts for it
```

(Use OpenSSL 3+, e.g. Homebrew's, not macOS's LibreSSL. Without the padding
line, macOS `base64 -d` silently drops the key's last bytes.) With this repo
at hand, `x kdf -m - <id> <name>` reads the master key from stdin, without
`op`.

### Sharing with someone

`x vault share [--to /Applications] <path>` seals with a fresh random
passphrase (gzip, because stock macOS `tar` can't read zstd; no padding), uploads
to `Vault/shares/`, makes an anyone-with-the-link URL and copies a message:
the link plus

```sh
curl -fsSL https://raw.githubusercontent.com/<you>/dotfiles/<commit>/x/.config/x/share/open.sh | bash -s -- <passphrase> <file>.age
```

The URL pins the commit of `share/open.sh`, so commit and push it before
sharing. The script fetches a pinned, checksum-verified `age` into a temp
folder, decrypts, shows what goes where, and asks first. Anyone holding the
message can open that one file; it shares nothing with your master keys.

### Notes

- macOS `tar` stores names in decomposed Unicode (`é` as `e` + accent).
  APFS treats both forms as the same name. Only byte-wise tools like `diff -r`
  notice.
- Archives keep permissions, symlinks, ACLs and extended attributes (Finder
  tags, quarantine, …). Shares (`--portable`) leave out the macOS-only parts
  so other systems don't get `._` files. Sealing a path that is itself a
  symlink seals what it points to.
- Every vault command picks archives the same way: by archive name, exact
  path, any part of the original path, or a glob on it.
- Deletions on Drive (`rm`, the old copy after a `rekey`, a replaced index)
  go to Drive's trash, which counts against your quota for 30 days. Rekeying
  a lot of data briefly needs that much extra room.
- `x vault check` lists archives on Drive missing from the index (e.g. after
  an interrupted rekey) and vice versa.

## Backup with GNU stow

This directory is self-contained and position-agnostic: `x.zsh` resolves its
own real path at runtime, so it doesn't matter where the enclosing repo is
cloned. Move it into a dotfiles repo mirroring `$HOME`:

```
dotfiles/                 # git repo, cloned anywhere
  x/                      # stow package
    .config/x/            # <- this directory
```

Then, from the repo root (wherever that is):

```sh
stow x            # symlinks ~/.config/x -> <repo>/x/.config/x
```

Because `x.zsh` resolves its own real path, autoloading keeps working through
the symlink — no matter where `<repo>` lives.
