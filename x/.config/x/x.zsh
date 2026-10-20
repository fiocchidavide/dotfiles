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
        printf "  %-12s %s\n" "$key" "${X_DESCRIPTIONS[$key]}"
    done
    # surface any autoloaded x_* command that has no description
    local fn
    for fn in ${(ok)functions[(I)x_*]}; do
        key=${fn#x_}
        (( ${+X_DESCRIPTIONS[$key]} )) || printf "  %-12s %s\n" "$key" "(no description)"
    done
}

# dispatcher
x() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        print "👋 Usage: x <command> [args...]"
        print "Available commands:"
        _x_print_commands
        return 1
    fi
    shift

    local fn="x_${cmd}"
    if (( ${+functions[$fn]} )); then        # only dispatch to our own functions
        "$fn" "$@"
    else
        print "❌ Error: 'x $cmd' is not a known command."
        print "Available commands:"
        _x_print_commands
        print "Add one by creating '${X_FUNCTIONS_DIR/#$HOME/~}/x_${cmd}'."
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
    print -u2 "❌ Missing setting(s): ${(j:, :)unset_vars}"
    print -u2 "   Set them in ${X_DIR/#$HOME/~}/config.zsh (see config.zsh.example)."
    return 1
}

# Like _x_need_config for a single setting, but asks for a missing value on
# the terminal (offering a default) and remembers it in config.zsh.
#   _x_ask_config X_FOO_DIR "Folder for foo" ~/foo || return
_x_ask_config() {
    local var=$1 question=$2 default=$3 value
    [[ -n ${(P)var} && ${(P)var} != *'<'*'>'* ]] && return 0
    if ! _x_ask "value" "❓ $question${default:+ [$default]}: "; then
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
# output helpers: status lines, spinners and progress bars
# ============================================================================
# Status goes to stderr so stdout stays clean for data (paths, keys, JSON).
# Colour and animation only on a terminal; NO_COLOR disables colour and
# X_QUIET=1 (commands map -q to it) silences spinners, progress bars and
# step/info/ok lines; warnings and errors always show.

_x_fancy() { [[ -t 2 && -z ${NO_COLOR-} ]] }

# _x_say <sgr> <icon> <message…>: one status line, icon coloured by <sgr>.
_x_say() {
    local sgr=$1 icon=$2; shift 2
    if _x_fancy; then
        print -u2 -r -- $'\e['"${sgr}m${icon}"$'\e[0m'" $*"
    else
        print -u2 -r -- "$icon $*"
    fi
}
_x_step() { (( ${X_QUIET:-0} )) && return; _x_fancy && print -u2 -r -- $'\e[1;34m▸ \e[0;1m'"$*"$'\e[0m' || print -u2 -r -- "▸ $*" }
_x_info() { (( ${X_QUIET:-0} )) && return; _x_fancy && print -u2 -r -- $'\e[2m  '"$*"$'\e[0m' || print -u2 -r -- "  $*" }
_x_ok()   { (( ${X_QUIET:-0} )) || _x_say 32 ✅ "$@" }
_x_warn() { _x_say 33 ⚠️ "$@" }
_x_err()  { _x_say 31 ❌ "$@" }

# Seconds since $1 (an $EPOCHREALTIME), formatted 4.2s / 3:07 / 1:02:03.
_x_elapsed() {
    zmodload zsh/datetime
    local -i s=$(( EPOCHREALTIME - $1 ))
    if (( s < 60 )); then
        printf '%.1fs' $(( EPOCHREALTIME - $1 ))
    elif (( s < 3600 )); then
        printf '%d:%02d' $(( s / 60 )) $(( s % 60 ))
    else
        printf '%d:%02d:%02d' $(( s / 3600 )) $(( s / 60 % 60 )) $(( s % 60 ))
    fi
}

# _x_spin [-t] <label> <cmd…>: run cmd with a spinner and elapsed time beside
# the label, then leave a single ✅/❌ line (-t: no line on success). cmd's
# stdout passes through untouched (so `key=$(_x_spin "Reading key" op read …)`
# works); its exit status is kept.
_x_spin() {
    emulate -L zsh
    setopt no_monitor no_notify
    zmodload zsh/datetime zsh/zselect
    local transient=0
    [[ $1 == -t ]] && { transient=1; shift }
    local label=$1; shift
    local t0=$EPOCHREALTIME rc=0
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
            printf '\r\e[K\e[36m%s\e[0m %s \e[2m%s\e[0m' \
                "${frames[i % 10 + 1]}" "$label" "$(_x_elapsed $t0)" >&2
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
        _x_ok "$label $(_x_fancy && print -n $'\e[2m')($(_x_elapsed $t0))$(_x_fancy && print -n $'\e[0m')"
    fi
    return rc
}

# _x_pv [-s bytes] [-N label]: progress bar for a byte stream in a pipeline,
# or a plain pass-through when quiet, not on a terminal, or pv is missing.
#   tar -cf - dir | _x_pv -s $bytes -N "dir" | zstd …
_x_pv() {
    local -a size name
    zparseopts -D -E -- s:=size N:=name
    if ! _x_fancy || (( ${X_QUIET:-0} )) || (( ! $+commands[pv] )); then
        cat
        return
    fi
    local -a opts=(--progress --bytes --rate --timer --eta --width 80 --bar-style granular)
    [[ -n ${size[2]} ]] && (( size[2] > 0 )) && opts+=(--size ${size[2]})
    [[ -n ${name[2]} ]] && opts+=(--name "${name[2]}")
    pv "${opts[@]}"
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
    _x_ask reply "❓ $1 [y/N] " || return 1
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
