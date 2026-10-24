#!/usr/bin/env zsh
# Unit checks for pure helpers: x.zsh's formatting, x rveil's archive
# matching, and how xstream.py draws rveil's log.
#   zsh -f .github/scripts/units.zsh      (needs uv and jq)
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

# --- x rveil -------------------------------------------------------------------
# Running x_rveil defines its helpers; an unknown subcommand stops it there.
XDG_STATE_HOME=$work/state x_rveil no-such-sub 2>/dev/null || true

recs='{"id":"abcdef.aaaaaaaaaaaaaaaaaaaaaaaaaa","name":"Photos","kind":"dir"}
{"id":"abcdef.bbbbbbbbbbbbbbbbbbbbbbbbbb","name":"Photos 2019","kind":"dir"}
{"id":"abcdef.cccccccccccccccccccccccccc","name":"tax.pdf","kind":"file"}'
# picks <match> <names…>: the archives a match selects, by name.
picks() { eq "$(_x_rveil_match $1 <<<$recs | jq -r .name | paste -sd, -)" "${(j:,:)@[2,-1]}" "match '$1'" }
picks photos      Photos                 # a whole name: that archive only
picks PHOTOS      Photos
picks phot        Photos 'Photos 2019'   # a piece: every name containing it
picks 2019        'Photos 2019'
picks abcdef.cccccccccccccccccccccccccc     tax.pdf
picks abcdef.cccccccccccccccccccccccccc.age tax.pdf
picks abcdef      ''                     # a key id isn't a name
picks nope        ''

# --- xstream.py rveillog -------------------------------------------------------
# Off a terminal: outcomes, notices and errors as role lines (icon, text);
# steps, progress and debug lines only drive the live line, so none print.
local log
log=$(print -r -- '{"level":"info","event":"start","step":"upload","msg":"Uploading"}
{"level":"info","event":"progress","step":"upload","bytes":5,"total":10,"msg":"x"}
{"level":"debug","event":"end","step":"upload","msg":"done"}
{"level":"info","event":"archive","msg":"tax.pdf: pushing"}
{"level":"info","event":"pushed","msg":"tax.pdf: on the remote"}
{"level":"info","event":"sizes","msg":"sizes"}
{"level":"notice","event":"odd","msg":"look"}
{"level":"error","event":"fatal","msg":"broke"}' |
    uv run --quiet --no-project python -I $repo/x/.config/x/lib/xstream.py rveillog \
        --role step S 1 --role ok O 32 --role info I 2 --role warn W 33 --role err E 31 2>&1)
eq "$log" $'S tax.pdf: pushing\nO tax.pdf: on the remote\nI sizes\nW look\nE broke' "rveillog lines"
log=$(print -r -- '{"level":"info","event":"pushed","msg":"ok"}
{"level":"error","event":"fatal","msg":"broke"}' |
    X_QUIET=1 uv run --quiet --no-project python -I $repo/x/.config/x/lib/xstream.py rveillog \
        --role ok O 32 --role err E 31 2>&1)
eq "$log" "E broke" "rveillog X_QUIET"

if (( $#failures )); then
    print -u2 -l -- "${#failures} unit check(s) failed:" "  "${^failures}
    exit 1
fi
print "units ok"
