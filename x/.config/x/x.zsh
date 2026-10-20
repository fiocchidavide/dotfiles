# ============================================================================
# `x` — a tiny, lazy-loading subcommand dispatcher for personal shell helpers.
#
# LAYOUT (this whole directory is self-contained and stow/git friendly)
#   ~/.config/x/
#     x.zsh                     <- this file: dispatcher, help, completion
#     functions/
#       x_<name>                <- one command per file (autoloaded on demand)
#       _x_<name>_complete      <- optional completion hook for that command
#
# HOW TO ADD A NEW COMMAND
#   1. Create an executable-style function file `functions/x_<name>` whose
#      contents are the *body* of the command (no `x_<name>() { ... }` wrapper —
#      that's the zsh autoload convention).
#   2. Make the FIRST `## ` line in that file its description. It shows up in
#      `x` help and tab-completion. No separate registry to keep in sync.
#   3. (Optional) For sub-argument completion, add `functions/_x_<name>_complete`
#      (also body-only); `_x` calls it automatically. Otherwise, add <name> to
#      the `_files` case in `_x` if it takes a path argument.
#
#   Example — functions/x_hello:
#       ## say hello to someone
#       print "Hi, ${1:-world}!"
#
#   Then: `x hello`, `x` (lists it), `x he<TAB>` (completes it). No reload of
#   the whole file — only x_hello's body is compiled, and only when first run.
#
# Re-run `_x_build_descriptions` in a live shell after editing descriptions.
# ============================================================================

typeset -g  X_DIR X_FUNCTIONS_DIR
typeset -gA X_DESCRIPTIONS

# One-time setup: locate our own directory (symlink/stow-safe), put functions/
# on fpath, and mark every command + completion hook for lazy autoloading.
_x_init() {
    local self=${${(%):-%x}:A}      # absolute, symlink-resolved path of this file
    X_DIR=${self:h}
    X_FUNCTIONS_DIR=$X_DIR/functions

    fpath=($X_FUNCTIONS_DIR $fpath)
    # autoload registers a stub in $functions; the body is compiled on first call.
    autoload -Uz $X_FUNCTIONS_DIR/x_*(N:t) $X_FUNCTIONS_DIR/_x_*_complete(N:t)

    _x_build_descriptions
}

# Build the description map by reading only the leading `## ` line of each
# command file — no sourcing, so this stays cheap even with many commands.
_x_build_descriptions() {
    X_DESCRIPTIONS=()
    local f name line
    for f in $X_FUNCTIONS_DIR/x_*(N); do
        name=${${f:t}#x_}
        while IFS= read -r line; do
            if [[ $line == '## '* ]]; then
                X_DESCRIPTIONS[$name]=${line#\#\# }
                break
            elif [[ $line == '#'* || -z $line ]]; then
                continue                     # skip shebang/other comments/blanks
            else
                break                        # hit code before a `## ` line
            fi
        done < $f
    done
}

_x_print_commands() {
    local key
    for key in ${(ok)X_DESCRIPTIONS}; do
        _x_row "$key" "${X_DESCRIPTIONS[$key]}"
    done
    # surface any autoloaded x_* command that has no description
    local fn
    for fn in ${(ok)functions[(I)x_*]}; do
        key=${fn#x_}
        (( ${+X_DESCRIPTIONS[$key]} )) || _x_row "$key" "(no description)"
    done
}

# dispatcher
x() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        _x_usage "x <command> [args...]"
        _x_heading "Commands"
        _x_print_commands
        return 1
    fi
    shift

    local fn="x_${cmd}"
    if (( ${+functions[$fn]} )); then        # only dispatch to our own functions
        "$fn" "$@"
    else
        _x_err "'x $cmd' is not a known command."
        _x_info "Run x for the list, or add it as ${X_FUNCTIONS_DIR/#$HOME/~}/x_${cmd}."
        return 1
    fi
}

_x_init

# Personal settings (usernames, 1Password references, …) live in a git-ignored
# config.zsh next to this file; config.zsh.example documents every key.
[[ -r $X_DIR/config.zsh ]] && source $X_DIR/config.zsh

# Fail with a pointer to config.zsh unless every named setting is filled in.
# Values still holding an `<placeholder>` from the example count as unset.
#   _x_need_config X_FOO_USER X_FOO_PASSWORD_REF || return
_x_need_config() {
    local var
    local -a unset_vars
    for var in "$@"; do
        [[ -z ${(P)var} || ${(P)var} == *'<'*'>'* ]] && unset_vars+=$var
    done
    (( ${#unset_vars} )) || return 0
    _x_err "Missing setting(s): ${(j:, :)unset_vars}"
    _x_info "Set them in ${X_DIR/#$HOME/~}/config.zsh (see config.zsh.example)."
    return 1
}

# Like _x_need_config for a single setting, but asks for a missing value on
# the terminal (offering a default) and remembers it in config.zsh.
#   _x_ask_config X_FOO_DIR "Folder for foo" ~/foo || return
_x_ask_config() {
    local var=$1 question=$2 default=$3 value
    [[ -n ${(P)var} && ${(P)var} != *'<'*'>'* ]] && return 0
    if ! _x_ask "value" "$(_x_icon ask) $question${default:+ [$default]}: "; then
        # No terminal and nothing on stdin: take the default if there is one.
        if [[ -z $default ]]; then
            _x_need_config $var
            return
        fi
        value=$default
        _x_info "No answer possible here; using the default."
    fi
    value=${value:-$default}
    if [[ -z $value ]]; then
        _x_err "No value given for $var."
        return 1
    fi
    typeset -g $var=$value
    print -r -- "$var=${(qq)value}" >> $X_DIR/config.zsh
    _x_info "Saved $var in ${X_DIR/#$HOME/~}/config.zsh"
}

# ============================================================================
# output helpers: the x design language
# ============================================================================
# Every command speaks through these, so all of x looks the same: one Nerd Font
# icon and colour per role (X_ICONS, X_COLORS), no ad-hoc emoji or escapes.
#
#   _x_step   doing something (bold)           _x_ok    it worked
#   _x_info   a detail or hint (dim)           _x_warn  worth knowing, not fatal
#   _x_usage  how to call a command            _x_err   it failed
#   _x_heading / _x_row / _x_item / _x_mark    reports (lists, status, doctor)
#
# Status lines (step/info/ok/warn/err/usage) go to stderr so stdout stays clean
# for data (paths, keys, JSON); reports a command was asked for go to stdout.
# Colour and animation only on a terminal; NO_COLOR disables colour and
# X_QUIET=1 (commands map -q to it) silences spinners, progress bars and
# step/info/ok lines; warnings and errors always show.

# _x_fancy [fd]: whether output on fd (default 2, stderr) gets colour.
_x_fancy() { [[ -t ${1:-2} && -z ${NO_COLOR-} ]] }

# Nerd Font icons (Material Design, outlined), one place to restyle them all.
typeset -gA X_ICONS=(
    step $'\U000f0142'   # md-chevron_right
    info $'\U000f02fd'   # md-information_outline
    ok   $'\U000f05e1'   # md-check_circle_outline
    warn $'\U000f05d6'   # md-alert_circle_outline
    err  $'\U000f015a'   # md-close_circle_outline
    ask  $'\U000f0625'   # md-help_circle_outline
    key  $'\U000f030b'   # md-key_variant
    on   $'\U000f0765'   # md-checkbox_blank_circle   (running, present)
    half $'\U000f1396'   # md-circle_half_full        (partly up)
    off  $'\U000f0766'   # md-checkbox_blank_circle_outline (off, absent)
)

# SGR colour per role (and for the spinner and plain text styles).
typeset -gA X_COLORS=(
    step '1;34'  info 36  ok 32  warn 33  err 31  ask 35  key 33
    on 32  half 33  off 2
    spin 36  bold 1  dim 2
)

# _x_paint [-o] <style> <text…>: text in an X_COLORS style (or a raw SGR) when
# stderr is a terminal (-o: stdout). Prints no newline. Inside $(…) stdout is
# a pipe, so -o trusts X_FANCY_OUT when a report helper has set it.
_x_paint() {
    local fancy
    if [[ $1 == -o ]]; then
        shift
        fancy=${X_FANCY_OUT:-$(_x_fancy 1 && print 1)}
    else
        _x_fancy && fancy=1
    fi
    local sgr=${X_COLORS[$1]:-$1}; shift
    if [[ -n $fancy ]]; then
        print -rn -- $'\e['"${sgr}m$*"$'\e[0m'
    else
        print -rn -- "$*"
    fi
}

# _x_icon [-o] <name> [sgr]: the icon in its role colour (or sgr).
_x_icon() {
    local -a o
    [[ $1 == -o ]] && { o=(-o); shift }
    _x_paint $o ${2:-${X_COLORS[$1]:-0}} ${X_ICONS[$1]}
}

# _x_say <role> <message…>: one status line on stderr, icon in the role colour.
_x_say() {
    local role=$1; shift
    print -u2 -r -- "$(_x_icon $role) $*"
}
_x_step() { (( ${X_QUIET:-0} )) || _x_say step "$(_x_paint bold "$*")" }
_x_info() { (( ${X_QUIET:-0} )) || _x_say info "$(_x_paint dim "$*")" }
_x_ok()   { (( ${X_QUIET:-0} )) || _x_say ok "$@" }
_x_warn() { _x_say warn "$@" }
_x_err()  { _x_say err "$@" }

# _x_usage <synopsis> [detail…]: "Usage: <synopsis>", then each detail line
# dim and indented, on stderr.
_x_usage() {
    print -u2 -r -- "$(_x_paint bold Usage:) $1"
    shift
    local line
    for line in "$@"; do
        print -u2 -r -- "  $(_x_paint dim "$line")"
    done
}

# Reports on stdout: a bold heading, aligned name/description rows, and items
# led by a role icon (on/half/off for state, ok/err for checks).
#   _x_heading "Commands"; _x_row vault "encrypted backups"
#   _x_item on "webdav  ~/WebDAV → https://…"
#   _x_mark ok jq; _x_mark err fzf; print     # inline marks, one line
_x_heading() {
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    print -r -- "$(_x_paint -o bold "$*")"
}
_x_row() {
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    local name=$1; shift
    print -r -- "  $(_x_paint -o bold ${(r:12:)name}) $(_x_paint -o dim "$*")"
}
_x_item() {
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    local role=$1; shift
    print -r -- "  $(_x_icon -o $role) $*"
}
_x_mark() {
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    print -rn -- "$(_x_icon -o $1) $2  "
}

# Seconds since $1 (an $EPOCHREALTIME), formatted 4.2s / 3:07 / 1:02:03.
_x_elapsed() {
    zmodload zsh/datetime
    local -F t=$(( EPOCHREALTIME - $1 ))
    local -i s=$t
    if (( t < 59.95 )); then            # %.1f would round anything above to 60.0
        printf '%.1fs' $t
    elif (( s < 3600 )); then
        printf '%d:%02d' $(( s / 60 )) $(( s % 60 ))
    else
        printf '%d:%02d:%02d' $(( s / 3600 )) $(( s / 60 % 60 )) $(( s % 60 ))
    fi
}

# _x_spin [-t] <label> <cmd…>: run cmd with a spinner and elapsed time beside
# the label, then leave a single success/error line (-t: none on success). cmd's
# stdout passes through untouched (so `key=$(_x_spin "Reading key" op read …)`
# works); its exit status is kept.
_x_spin() {
    # Not emulate -L zsh: cmd runs in this scope, so it must keep the caller's
    # options (pipe_fail, extended_glob, …).
    setopt local_options no_monitor no_notify
    zmodload zsh/datetime zsh/zselect
    local transient=0
    [[ $1 == -t ]] && { transient=1; shift }
    local label=$1; shift
    local t0=$EPOCHREALTIME rc=0
    # Inside another spinner, just run: two would redraw the same line.
    if (( ${X_SPINNING:-0} )); then
        "$@"
        return
    fi
    local X_SPINNING=1
    if ! _x_fancy || (( ${X_QUIET:-0} )); then
        "$@" || rc=$?
        if (( rc )); then
            _x_err "$label failed"
        elif (( ! transient && ! ${X_QUIET:-0} )); then
            _x_ok "$label ($(_x_elapsed $t0))"
        fi
        return rc
    fi
    {
        local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
        while :; do
            printf '\r\e[K\e[%sm%s\e[0m %s \e[%sm%s\e[0m' \
                ${X_COLORS[spin]} "${frames[i % 10 + 1]}" "$label" \
                ${X_COLORS[dim]} "$(_x_elapsed $t0)" >&2
            (( i++ ))
            zselect -t 10
        done
    } &!
    local spinner=$!
    {
        "$@" || rc=$?
    } always {
        kill $spinner 2>/dev/null
        printf '\r\e[K' >&2
    }
    if (( rc )); then
        _x_err "$label failed ($(_x_elapsed $t0))"
    elif (( ! transient )); then
        _x_ok "$label $(_x_paint dim "($(_x_elapsed $t0))")"
    fi
    return rc
}

# _x_pv [-s bytes] [-N label]: progress bar for a byte stream in a pipeline
# (same renderer as x gdrive's transfers), or a plain pass-through when
# quiet or not on a terminal.
#   tar -cf - dir | _x_pv -s $bytes -N "dir" | zstd …
_x_pv() {
    local -a size name
    zparseopts -D -E -- s:=size N:=name
    if ! _x_fancy || (( ${X_QUIET:-0} )); then
        cat
        return
    fi
    uv run --quiet --no-project python -I $X_DIR/lib/xstream.py meter \
        --size ${size[2]:-0} --label "${name[2]:-}"
}

# _x_ask <var> <prompt> [-s]: read a line from the terminal (stdin when there
# is no terminal) into <var>; -s hides the input.
_x_ask() {
    local -a silent
    [[ $3 == -s ]] && silent=(-s)
    if { : </dev/tty } 2>/dev/null; then
        read -r $silent "$1?$2" </dev/tty || return
        if (( $#silent )); then
            print -u2
        fi
    else
        print -u2 -n -- "$2"
        read -r $silent "$1" || return
        print -u2
    fi
}

# _x_ask_yn <question>: y/N; succeeds only on an explicit y.
_x_ask_yn() {
    local reply
    _x_ask reply "$(_x_icon ask 35) $1 [y/N] " || return 1
    [[ $reply == [yY]* ]]
}

# _x_bytes <n>: human-readable size (1.2 GiB).
_x_bytes() {
    local -F n=$1
    local -a units=(B KiB MiB GiB TiB PiB)
    local i=1
    while (( n >= 1024 && i < ${#units} )); do
        (( n /= 1024, i++ ))
    done
    (( i == 1 )) && printf '%d B' $n || printf '%.1f %s' $n ${units[i]}
}

# ============================================================================
# completion for `x <subcommand> [args...]`
# ============================================================================
_x() {
    if (( CURRENT == 2 )); then
        local -a subcmds
        local key
        for key in ${(ok)X_DESCRIPTIONS}; do
            subcmds+=("$key:${X_DESCRIPTIONS[$key]}")
        done
        _describe 'x command' subcmds
        return
    fi

    # Delegate to a per-command hook if one exists (e.g. _x_ramdisk_complete).
    local hook="_x_${words[2]}_complete"
    if (( ${+functions[$hook]} )); then
        "$hook"
        return
    fi

    # Fallback: complete file paths for commands that take one.
    case "${words[2]}" in
        extrct|ocr|copypath|undmg|seal|unseal) _files ;;
        *) ;;
    esac
}
compdef _x x
