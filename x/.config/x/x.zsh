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
# HOW TO ADD A NEW COMMAND (`x new <name>` scaffolds all of this)
#   1. Create an executable-style function file `functions/x_<name>` whose
#      contents are the *body* of the command (no `x_<name>() { ... }` wrapper —
#      that's the zsh autoload convention).
#   2. Make the FIRST `## ` line in that file its description. It shows up in
#      `x` help and tab-completion. No separate registry to keep in sync.
#   3. Write a `# Usage: x <name> …` comment block: the command's shape, then
#      one `#   x <name> …` line per form, 3 spaces in, then 2+ spaces and what
#      it does. It is the command's help and the source of its subcommands
#      (see _x_synopses and _x_help): `x <name> -h`,
#      `x <name> <sub> --help`, unknown or missing subcommands and completing
#      subcommand words all come from it, so the command implements none of it.
#   4. Complete what follows the subcommands (files, options, values) with
#      `functions/_x_<name>_complete` (also body-only), or add <name> to the
#      `_files` case in `_x` if it takes a path.
#
#   Example — functions/x_hello:
#       ## say hello to someone
#       # Usage: x hello [name]
#       #
#       # Greets name (default: world).
#
#       print "Hi, ${1:-world}!"
#
#   Then: `x hello`, `x` (lists it), `x he<TAB>` (completes it), `x hello -h`.
#   No reload of the whole file — only x_hello's body is compiled, and only
#   when first run. .github/scripts/discover.zsh checks every command in CI.
#
# Re-run `_x_build_descriptions` in a live shell after editing descriptions.
# ============================================================================

typeset -g  X_DIR X_FUNCTIONS_DIR
typeset -gA X_DESCRIPTIONS X_SYNOPSES

# $EPOCHREALTIME, for _x_elapsed and every `t0=$EPOCHREALTIME` in commands.
zmodload zsh/datetime

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
    X_DESCRIPTIONS=() X_SYNOPSES=()
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
    if [[ -z "$cmd" || $cmd == (-h|--help) ]] || [[ $cmd == help && $# == 1 ]]; then
        # Laid out like a command's help (_x_help): the shape, the forms, then
        # the commands. Asked for: stdout; nothing given: stderr, an error.
        {
            local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
            print -r -- "$(_x_paint -o bold Usage:) x <command> [args...]"
            print
            print -r -- "  $(_x_paint -o bold 'x <command> -h                ')    $(_x_paint -o dim "a command's help")"
            print -r -- "  $(_x_paint -o bold 'x help <command> [subcommand…]')    $(_x_paint -o dim 'the same, or one subcommand'"'"'s')"
            print
            _x_heading "Commands:"
            _x_print_commands
        } >&${${cmd:+1}:-2}
        [[ -n $cmd ]]
        return
    fi
    shift
    if [[ $cmd == help ]]; then             # x help vault put = x vault put --help
        x "$@" --help
        return
    fi

    local fn="x_${cmd}"
    if (( ! ${+functions[$fn]} )); then      # only dispatch to our own functions
        _x_err "'x $cmd' is not a known command."
        _x_info "Run x for the list, or add it as ${X_FUNCTIONS_DIR/#$HOME/~}/x_${cmd}."
        return 1
    fi

    # Help and subcommand checks, from the command's Usage block and the same
    # for every command, so commands implement none of it:
    #   x vault -h | --help | help      the whole block, on stdout
    #   x vault keys -h | --help        the `x vault keys …` lines
    #   x ramdisk                       subcommand missing: the block, on stderr
    #   x ramdisk nope                  unknown subcommand: an error
    local -a subs kids kid_descs opt_descs kid_aliases opts valued
    local bare pure word
    local -i i=1
    while (( i <= $# )); do
        _x_usage_info $cmd $subs
        word=${@[i]}
        if (( ${valued[(Ie)$word]} )); then     # x gdrive -r <remote> up
            (( i += 2 ))
            continue
        fi
        if (( ! ${kids[(Ie)$word]} )); then
            word=${${kid_aliases[(r)$word=*]}#*=}
            [[ -n $word ]] || break
        fi
        subs+=$word
        (( i++ ))
    done
    _x_usage_info $cmd $subs
    local next=${@[i]-}
    if (( i <= $# )) && [[ $next == (-h|--help) || ( $next == help && $# == 1 ) ]]; then
        _x_help -o $cmd $subs
        return
    fi
    if (( $#kids )); then
        if (( i > $# && ! bare )); then
            _x_help $cmd $subs
            return
        elif (( i <= $# && pure )) && [[ $next != -* ]]; then
            _x_err "Unknown subcommand: ${${:-x $cmd ${subs[*]}}% } $next"
            _x_help $cmd $subs
            return
        fi
    fi
    "$fn" "$@"
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
        # On a terminal that was Ctrl-D: a "no", so save nothing and stop.
        if { : </dev/tty } 2>/dev/null; then
            _x_warn "Stopped; $var stays unset."
            return 1
        fi
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
    local config=$X_DIR/config.zsh
    # Start on a fresh line even if the file's last line has no newline.
    [[ -s $config && -n $(tail -c 1 $config) ]] && print >> $config
    print -r -- "$var=${(qq)value}" >> $config
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
#   _x_help   a command's help (Usage block)   _x_err   it failed
#   _x_heading / _x_row / _x_item / _x_mark    reports (lists, status, doctor)
#
# Status lines (step/info/ok/warn/err, and help shown for misuse) go to stderr
# so stdout stays clean for data (paths, keys, JSON); reports a command was
# asked for go to stdout, and so does help asked for with -h/--help (_x_help -o).
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

# _x_usage [-o] <synopsis> [detail…]: "Usage: <synopsis>", then each detail
# line dim and indented, on stderr; -o (help that was asked for, -h/--help):
# on stdout. Only for x itself: a command's help is its Usage block (_x_help).
_x_usage() {
    local -a paint=() fd=(-u2)
    [[ $1 == -o ]] && { paint=(-o) fd=(); shift }
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    print $fd -r -- "$(_x_paint $paint bold Usage:) $1"
    shift
    local line
    for line in "$@"; do
        print $fd -r -- "  $(_x_paint $paint dim "$line")"
    done
}

# A command's `# Usage:` block, from that line to the first blank or
# non-comment line, is its help. The Usage line gives the command's shape;
# synopsis lines below read `#   x <cmd> …`, 3 spaces in, with what they do
# after 2+ spaces or on the indented lines below:
#   # Usage: x vault <command> …
#   #
#   #   x vault keys                list master keys
#   #   x vault keys new [--use]    create one
#   #   x vault rm [-n] <archive>…
#   #                               delete archives
# Leading plain words after `x <cmd>` are subcommands ("keys", "keys new");
# `off|stop` names one with its aliases.

# _x_usage_block <cmd>: the lines of x_<cmd>'s Usage block, `#` stripped.
_x_usage_block() {
    awk '/^# Usage:/ { f = 1 } f && !/^#/ { exit } f { sub(/^#/, ""); print }' \
        $X_FUNCTIONS_DIR/x_$1 2>/dev/null
}

# _x_synopses <cmd>: its synopses, one per line:
# "<path>\t<args>\t<what>\t<aliases>\t<kind>", <path> being the command and
# its subcommand words ("vault keys new"), <args> the rest of the synopsis,
# <what> its description, <aliases> other names for the path's last word and
# <kind> "shape" for the Usage line itself, "option" for an option line
# ("<cmd>\t-k\t<what>").
_x_synopses() {
    emulate -L zsh
    setopt extended_glob
    if (( ! ${+X_SYNOPSES[$1]} )); then
        local -a lines out toks subs
        lines=("${(@f)$(_x_usage_block $1)}")
        local -i i j
        local line syn what next tok
        local -a alts
        syn=${lines[1]# Usage: }
        if [[ $syn == "x $1"(| *) ]]; then
            toks=(${=syn})
            out+=("$1"$'\t'"${toks[3,-1]}"$'\t\t\t'shape)
        fi
        for (( i = 1; i <= $#lines; i++ )); do
            line=${lines[i]}
            [[ $line == ("   x $1"(| *)|'   -'[A-Za-z-]*) ]] || continue
            line=${line#   }
            syn=${line%%  *}
            what=${${line#"$syn"}##[[:space:]]#}
            # the description goes on over the more indented lines below
            for (( j = i + 1; j <= $#lines; j++ )); do
                next=${lines[j]}
                [[ $next == '    '* && ${next##[[:space:]]#} != ('x '|-)* ]] || break
                what+=${what:+ }${next##[[:space:]]#}
            done
            if [[ $syn == -* ]]; then           # an option line: "-k keyid    …"
                out+=("$1"$'\t'"${syn%% *}"$'\t'"$what"$'\t\t'option)
                continue
            fi
            toks=(${=syn})
            subs=($1) alts=()
            for (( j = 3; j <= $#toks; j++ )); do
                tok=${toks[j]}
                [[ $tok == [a-z][a-z0-9-]#(\|[a-z][a-z0-9-]#)# ]] || break
                alts=(${(s:|:)tok})
                subs+=${alts[1]}
            done
            out+=("${subs[*]}"$'\t'"${toks[j,-1]}"$'\t'"$what"$'\t'"${alts[2,-1]}")
        done
        X_SYNOPSES[$1]=${(F)out}
    fi
    print -r -- ${X_SYNOPSES[$1]}
}

# _x_usage_info <cmd> [sub…]: what the Usage block says may follow that
# (sub)command. Sets the caller's locals: kids (its subcommands), kid_descs
# ("sub:what", for _describe), opt_descs (the same for its options),
# kid_aliases ("alias=sub"), opts (options in its
# synopses), valued (those that take a value: `[-r remote]`), bare (1: runs
# with nothing after it) and pure (1: whatever follows is a subcommand or an
# option, never a value).
_x_usage_info() {
    emulate -L zsh
    setopt extended_glob
    local want="$*" rec p a what kid tok al
    local -a f
    local -A optwhat
    kids=() kid_descs=() opt_descs=() kid_aliases=() opts=() valued=() bare=0 pure=1
    for rec in "${(@f)$(_x_synopses $1)}"; do
        [[ -n $rec ]] || continue
        f=("${(@ps:\t:)rec}")
        p=$f[1] a=$f[2] what=$f[3]
        if [[ ${f[5]-} == option ]]; then
            [[ $p == $want ]] && optwhat[${f[2]}]=${f[3]}
            continue
        fi
        if [[ ${f[5]-} == shape ]]; then        # the shape: options only
            [[ $p == $want ]] || continue
            for tok in ${(M)${=a//[\[\]|=]/ }:#-[A-Za-z]*}; do
                (( ${opts[(Ie)$tok]} )) || opts+=$tok
            done
            while [[ $a =~ '\[(--?[A-Za-z][A-Za-z0-9-]*) [^]-][^]]*\]' ]]; do
                valued+=$match[1]
                a=${a#*"$MATCH"}
            done
            continue
        fi
        if [[ $p == "$want "* ]]; then
            kid=${${p#"$want "}%% *}
            if [[ $p == "$want $kid" ]]; then
                for al in ${=f[4]}; do kid_aliases+=$al=$kid; done
            fi
            (( ${kids[(Ie)$kid]} )) && continue
            kids+=$kid
            kid_descs+=("$kid:$what")
        elif [[ $p == $want ]]; then
            [[ -z $a ]] && bare=1
            [[ ${a%% *} == ('<'*|'['[^-]*) ]] && pure=0
            for tok in ${(M)${=a//[\[\]|=]/ }:#-[A-Za-z]*}; do
                (( ${opts[(Ie)$tok]} )) || opts+=$tok
            done
            while [[ $a =~ '\[(--?[A-Za-z][A-Za-z0-9-]*) [^]-][^]]*\]' ]]; do
                valued+=$match[1]
                a=${a#*"$MATCH"}
            done
        fi
    done
    for tok in $opts; do
        opt_descs+=("$tok${optwhat[$tok]:+:${optwhat[$tok]}}")
    done
}

# _x_help [-o] <command> [sub…]: the command's Usage block, or for a
# subcommand only its synopses. -o, help that was asked for (-h, --help,
# help): stdout, status 0. Otherwise, as the error for a missing or unknown
# subcommand: stderr, status 1.
#
# Rendered like the `x` command list: the Usage line with the command's
# shape, then each entry of the block (a 2-space indented line: a synopsis,
# an option, "(default)") as a bold term and its description in grey,
# aligned with the entries around it and wrapped to the terminal; indented
# lines below an entry continue its description. Prose stays as written, set
# off from the entries by a blank line.
_x_help() {
    emulate -L zsh
    setopt extended_glob
    local -a fd=(-u2) paint=()
    [[ $1 == -o ]] && { fd=() paint=(-o); shift }
    local X_FANCY_OUT; _x_fancy 1 && X_FANCY_OUT=1
    local cmd=$1; shift
    local -a want=(x $cmd "$@") lines kind term text sw
    local line t d shape
    local -i i j keep=1
    lines=("${(@f)$(_x_usage_block $cmd)}")
    (( $# )) || shape=${${lines[1]# Usage:}# }
    lines=("${(@)${(@)lines[2,-1]}# }")      # drop the Usage line and the 1-space margin

    # Parse into entries (term + description), prose and blank lines.
    for line in "${lines[@]}"; do
        if [[ $line == '  '[^[:space:]]* ]]; then
            t=${${line#  }%%  *}
            d=${${${line#  }#"$t"}##[[:space:]]#}
            if [[ $t == 'x '* ]] && (( $# )); then
                # a subcommand's help: only synopses whose words start with
                # $want's, any alias (off|stop) matching
                sw=(${=t})
                keep=1
                for (( j = 1; j <= $#want; j++ )); do
                    (( ${${(s:|:)sw[j]-}[(Ie)${want[j]}]} )) || { keep=0; break }
                done
            fi
            (( keep )) || continue
            kind+=entry term+=$t text+=$d
        elif [[ $line == '   '* ]]; then
            (( keep )) && [[ ${kind[-1]-} == entry ]] || continue
            d=${line##[[:space:]]#}
            text[-1]+=${text[-1]:+ }$d
        elif (( $# )); then
            keep=0                              # a subcommand's help: entries only
        elif [[ -z $line ]]; then
            kind+=blank term+='' text+=''
        else
            kind+=prose term+='' text+=$line
        fi
    done

    # Print: entries in aligned columns per run of entries (blank lines
    # between them don't end a run), terms longer than 44 columns with their
    # description below.
    local -i cols=${COLUMNS:-80} width n wrap r=1
    (( cols > 100 )) && cols=100
    local -a out words runof
    local -A runw                           # run of entries -> its term column
    for (( i = 1; i <= $#kind; i++ )); do
        case ${kind[i]} in
            prose) (( r++ )) ;;
            entry)
                runof[i]=$r
                (( ${#term[i]} <= 44 && ${#term[i]} > ${runw[$r]:-0} )) && runw[$r]=${#term[i]}
                ;;
        esac
    done
    out=("$(_x_paint $paint bold Usage:)${shape:+ $shape}")
    [[ -n $shape ]] && out+=('')
    for (( i = 1; i <= $#kind; i++ )); do
        case ${kind[i]} in
            blank)
                [[ -n ${out[-1]} ]] && out+=('')
                ;;
            prose)
                [[ ${kind[i-1]-} == entry ]] && out+=('')
                if [[ ${text[i]} == [^[:space:]]*: && ${kind[i-1]-} != prose ]]; then
                    out+=("$(_x_paint $paint bold ${text[i]})")    # a heading
                else
                    out+=(${text[i]})
                fi
                ;;
            entry)
                width=${runw[${runof[i]}]:-0}
                wrap=$(( cols - width - 6 ))
                (( wrap < 30 )) && wrap=30
                words=(${=text[i]})
                local -a dl=('')
                for t in $words; do
                    if [[ -n ${dl[-1]} ]] && (( ${#dl[-1]} + 1 + ${#t} > wrap )); then
                        dl+=$t
                    else
                        dl[-1]+=${dl[-1]:+ }$t
                    fi
                done
                if (( ${#term[i]} > width )); then
                    out+=("  $(_x_paint $paint bold ${term[i]})")
                    n=1
                else
                    out+=("  $(_x_paint $paint bold ${(r:width:)term[i]})")
                    n=0
                    [[ -n ${dl[1]} ]] && out[-1]+="    $(_x_paint $paint dim ${dl[1]})"
                    shift dl
                fi
                for t in $dl; do
                    out+=("  ${(l:width:)}    $(_x_paint $paint dim $t)")
                done
                ;;
        esac
    done
    while [[ $#out -gt 1 && -z ${out[-1]} ]]; do out[-1]=(); done
    (( $# )) && out+=('' "$(_x_paint $paint dim "All of x $cmd: x $cmd --help")")
    print $fd -rl -- "${out[@]}"
    [[ -n $paint ]]
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
    # no_bg_nice: renicing the spinner fails (and says so) where nice is denied.
    setopt local_options no_monitor no_notify no_bg_nice
    zmodload zsh/zselect
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
            _x_err "$label failed ($(_x_elapsed $t0))"
        elif (( ! transient )); then
            _x_ok "$label $(_x_paint dim "($(_x_elapsed $t0))")"
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
    } >/dev/null &!     # not stdout: inside $(…) it would hold the pipe open
    local spinner=$! n
    {
        "$@" || rc=$?
    } always {
        # Disowned, so no `wait` (and no job notice): give it up to 0.2s to
        # go, or a last frame can land after the line is cleared.
        kill $spinner 2>/dev/null
        for n in {1..20}; do
            kill -0 $spinner 2>/dev/null || break
            zselect -t 1
        done
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
        --size ${size[2]:-0} --label="${name[2]:-}"
}

# _x_ask <var> <prompt> [-s]: read a line from the terminal (stdin when there
# is no terminal) into <var>; -s hides the input.
_x_ask() {
    local -a silent
    [[ $3 == -s ]] && silent=(-s)
    if { : </dev/tty } 2>/dev/null; then
        # zsh prints read's prompt on stderr, which callers may have silenced
        # (cmd 2>/dev/null); the question belongs on the terminal regardless.
        # On EOF (Ctrl-D) still end the prompt's line.
        read -r $silent "$1?$2" </dev/tty 2>/dev/tty || { print >/dev/tty; return 1 }
        if (( $#silent )); then
            print >/dev/tty
        fi
    else
        print -u2 -rn -- "$2"
        read -r $silent "$1" || return
        print -u2
    fi
}

# _x_ask_yn <question>: y/N; succeeds only on an explicit y.
_x_ask_yn() {
    local reply
    _x_ask reply "$(_x_icon ask) $1 [y/N] " || return 1
    [[ $reply == [yY]* ]]
}

# _x_rand_b32 <n>: n random base32 characters (a-z2-7); rejection sampling
# keeps them uniform. head closing the pipe kills tr with SIGPIPE, which
# pipe_fail would report as failure, so it's off here.
_x_rand_b32() {
    setopt local_options no_pipe_fail
    LC_ALL=C tr -dc 'a-z2-7' </dev/urandom | head -c $1
}

# _x_rand_key: 32 random bytes as unpadded base64url, for keys and passphrases.
_x_rand_key() {
    head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n'
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
    # `x help <command> [subcommand…]` completes like the command itself.
    if [[ ${words[2]} == help ]] && (( CURRENT > 2 )); then
        words[2]=()
        (( CURRENT-- ))
    fi
    if (( CURRENT == 2 )); then
        local -a subcmds=('help:help for a command or subcommand')
        local key
        for key in ${(ok)X_DESCRIPTIONS}; do
            subcmds+=("$key:${X_DESCRIPTIONS[$key]}")
        done
        _describe 'x command' subcmds
        return
    fi
    local cmd=${words[2]}
    (( ${+X_DESCRIPTIONS[$cmd]} )) || return 1

    # Subcommand words come from the Usage block, for every command alike:
    # walk the ones already typed (skipping options and their values).
    local -a subs kids kid_descs opt_descs kid_aliases opts valued
    local bare pure w
    local -i i=3 value=0
    while (( i < CURRENT )); do
        _x_usage_info $cmd $subs
        w=${words[i]}
        (( ${kids[(Ie)$w]} )) || w=${${kid_aliases[(r)$w=*]}#*=}
        if [[ -n $w ]]; then
            subs+=$w
        elif (( ${valued[(Ie)${words[i]}]} )); then
            (( ++i == CURRENT )) && { value=1; break }   # completing its value
        elif [[ ${words[i]} != -* ]]; then
            break                               # past the subcommands
        fi
        (( i++ ))
    done
    _x_usage_info $cmd $subs
    if (( i == CURRENT && $#kids && ! value )); then
        _describe 'subcommand' kid_descs -- opt_descs
        (( pure )) && return
    fi

    # What follows the subcommands: the command's own hook, if it has one
    # (e.g. _x_ramdisk_complete), else a path for commands that take one.
    local hook="_x_${cmd}_complete"
    if (( ${+functions[$hook]} )); then
        "$hook"
        return
    fi
    case "${words[2]}" in
        cp|extrct|ocr|undmg) _files ;;
        *) ;;
    esac
}
compdef _x x
