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
        extrct|ocr|copypath) _files ;;
        *) ;;
    esac
}
compdef _x x
