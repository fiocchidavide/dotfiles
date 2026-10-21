#!/usr/bin/env zsh
# Unit checks for pure helpers: x.zsh's formatting, x vault's archive
# matching and size parsing, and xstream.py's Padmé padding (which a stock
# `zstd -d` must skip).
#   zsh -f .github/scripts/units.zsh      (needs uv and zstd)
emulate -L zsh
setopt err_exit pipe_fail extended_glob

repo=${0:A:h:h:h}
compdef() {}                      # x.zsh registers completion; no compinit here
source $repo/x/.config/x/x.zsh

work=$(mktemp -d)
trap 'rm -rf -- $work' EXIT

local -a failures
# eq <got> <want> <what>
eq() { [[ $1 == $2 ]] || failures+="$3: got '$1', want '$2'" }

# --- x.zsh ---------------------------------------------------------------------
eq "$(_x_bytes 0)" "0 B" "_x_bytes 0"
eq "$(_x_bytes 1023)" "1023 B" "_x_bytes 1023"
eq "$(_x_bytes 1536)" "1.5 KiB" "_x_bytes 1536"
eq "$(_x_bytes $(( 1 << 30 )))" "1.0 GiB" "_x_bytes 1 GiB"
eq "$(_x_elapsed $(( EPOCHREALTIME - 4.2 )))" "4.2s" "_x_elapsed 4.2"
eq "$(_x_elapsed $(( EPOCHREALTIME - 187 )))" "3:07" "_x_elapsed 187"
eq "$(_x_elapsed $(( EPOCHREALTIME - 3723 )))" "1:02:03" "_x_elapsed 3723"

# --- x vault -------------------------------------------------------------------
# Running x_vault defines its helpers; an unknown subcommand stops it there.
_x_ask_config() { return 0 }
X_VAULT_REMOTE_DIR=Vault X_VAULT_STAGING=$work/staging XDG_STATE_HOME=$work/state
x_vault no-such-sub 2>/dev/null || true

match()   { _x_vault_matches "$@" || failures+="should match: $*" }
nomatch() { ! _x_vault_matches "$@" || failures+="shouldn't match: $*" }
n=abcdef.abcdefghijklmnopqrstuvwxyz
match   $n /x/Photos $n
match   $n /x/Photos $n.age
match   $n $HOME/Photos '~/Photos/'
match   $n "$HOME/Photos [2019]" 'Photos [2019]'
match   $n /x/2019-03 '*/2019-*'
match   $n /x/y/disk.dmg '*.dmg'
nomatch $n /x/Photos Music
nomatch $n /x/Photos '['

eq "$(_x_vault_size 123)" 123 "_x_vault_size 123"
eq "$(_x_vault_size 500M)" 524288000 "_x_vault_size 500M"
eq "$(_x_vault_size 2G)" 2147483648 "_x_vault_size 2G"
eq "$(_x_vault_size 2GiB)" 2147483648 "_x_vault_size 2GiB"
eq "$(_x_vault_size 1.5T)" 1649267441664 "_x_vault_size 1.5T"
_x_vault_size 2X 2>/dev/null && failures+="_x_vault_size 2X: accepted"

# --- xstream.py ----------------------------------------------------------------
local xstream=(uv run --quiet --no-project python -I $repo/x/.config/x/lib/xstream.py)

# The frames for any size, up to several maximal frames, without the bytes:
# they must reach exactly the Padmé bucket, each one a valid skippable frame.
uv run --quiet --no-project python -I - $repo/x/.config/x/lib <<'PY' || failures+="padding_frames"
import sys
sys.path.insert(0, sys.argv[1])
import xstream as x

bad = []
for payload in (0, 1, 7, 8, 100, 4095, 4096, 4097, 10**6,
                2**32 - 9, 2**32, 2**33 + 5, 5 * 2**32 + 3):
    frames = list(x.padding_frames(payload))
    total = payload + sum(x.FRAME_HEADER + body for _, body in frames)
    if total != x.padme(payload + x.FRAME_HEADER):
        bad.append(f"{payload}: padded to {total}")
    for header, body in frames:
        if (header[:4] != x.SKIPPABLE_MAGIC or not 0 <= body <= 0xFFFFFFFF
                or int.from_bytes(header[4:], "little") != body):
            bad.append(f"{payload}: bad frame ({body} bytes)")
print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# End to end: a padded zstd stream decompresses to the original by itself.
local size want
for size in 1 1000 100000; do
    head -c $size /dev/urandom > $work/raw
    zstd -q -c $work/raw > $work/z
    $xstream pad < $work/z > $work/padded
    zstd -q -d -c $work/padded | cmp -s - $work/raw || failures+="pad $size: zstd -d differs"
    want=$($xstream padme $(( $(wc -c < $work/z) + 8 )))
    eq $(( $(wc -c < $work/padded) )) $want "pad $size: padded size"
done

if (( $#failures )); then
    print -u2 -l -- "${#failures} unit check(s) failed:" "  "${^failures}
    exit 1
fi
print "units ok"
