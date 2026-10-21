#!/usr/bin/env zsh
# Every x command is discoverable the same way. Its `# Usage:` block (see
# _x_synopses in x.zsh) gives its shape and names its subcommands; for the
# command and each of them this checks:
#   help      x <path> -h, --help, x help <path> (and x <cmd> help): status 0,
#             the synopses on stdout, nothing on stderr
#   errors    a missing or unknown subcommand: status 1, help on stderr
#   complete  x <path> <TAB> offers its subcommands and every option the
#             synopses document, and something for the arguments they show
#   source    every option the code parses (zparseopts) is documented, and the
#             dispatch `case` handles exactly the documented subcommands (and
#             their aliases)
# Help and errors must run nothing and ask for nothing: every tool a command
# declares (#@needs) is a stub that logs the call, and so is asking.
#   zsh -f .github/scripts/discover.zsh
emulate -L zsh
setopt extended_glob

repo=${0:A:h:h:h}
fns=$repo/x/.config/x/functions
work=$(mktemp -d)
trap 'rm -rf -- $work' EXIT

export X_TEST_LOG=$work/calls NO_COLOR=1
: >| $X_TEST_LOG
mkdir $work/bin
local tool line
local -a tools=(open pbcopy curl sudo pgrep pkill osascript)
for line in ${(f)"$(grep -h '^#@needs' $fns/x_*)"}; do
    tools+=(${=${line%%\#[^@]*}#\#@needs(-optional|)})
done
for tool in ${(u)tools}; do
    print -r -- '#!/bin/sh
echo "ran: ${0##*/} $*" >> "$X_TEST_LOG"
exit 97' > $work/bin/$tool
    chmod +x $work/bin/$tool
done
path=($work/bin $path)

compdef() {}                      # x.zsh registers completion; no compinit here
source $repo/x/.config/x/x.zsh
_x_ask()        { print -r -- "asked: $2" >> $X_TEST_LOG; return 1 }
_x_ask_config() { print -r -- "asked for $1" >> $X_TEST_LOG; return 1 }

local -a failures
fail() { failures+=("$*") }

# run <args…>: `x <args…>` in a subshell; sets out, err, rc and log (what it
# ran or asked).
local out err log
local -i rc
run() {
    : >| $X_TEST_LOG
    ( x "$@" ) >$work/out 2>$work/err </dev/null
    rc=$?
    out=$(<$work/out) err=$(<$work/err) log=$(<$X_TEST_LOG)
}

# Completion stubs: record what a completion offers instead of offering it.
_describe() {
    local a
    while [[ $1 == -* ]]; do [[ $1 == (-t|-O|-o) ]] && shift; shift; done
    shift                                            # the description
    local -i name=1
    for a in "$@"; do
        if [[ $a == -- ]]; then
            name=1
        elif (( name )); then
            print -rl -- "word ${(@)^${(@P)a}%%:*}"
            name=0
        fi
    done >> $work/comp
    print "act describe" >> $work/comp
}
_arguments() { print -rl -- "spec ${(@)^@}" "act arguments" >> $work/comp }
compadd()    { print -rl -- "word ${(@)^${@:#-*}}" "act compadd" >> $work/comp }
_files()     { print "act files" >> $work/comp }
_message()   { print "act message" >> $work/comp }
_urls()      { print "act urls" >> $work/comp }

# probe <word…>: completes `x <word…> <TAB>`; sets offered (words), copts
# (options from _arguments specs or offered) and acts (what was called).
local -a offered copts acts
probe() {
    : >| $work/comp
    (
        local -a words=(x "$@" '')
        local -i CURRENT=$#words
        local PREFIX=''
        _x
    ) >/dev/null 2>&1
    local l s
    offered=() copts=() acts=()
    for l in ${(f)"$(<$work/comp)"}; do
        case $l in
            'word '*) offered+=${l#word }
                      [[ ${l#word } == -* ]] && copts+=${l#word } ;;
            'spec '*) s=${${l#spec }#\(*\)}
                      s=${s#\*}
                      [[ $s == -* ]] && copts+=${(M)s##-[-A-Za-z0-9]##} ;;
            'act '*)  acts+=${l#act } ;;
        esac
    done
}

# options <text>: the option names (-x, --long) in it, one per line.
options() {
    local t
    for t in ${=${1//[^-A-Za-z0-9]/ }}; do
        [[ $t == -[A-Za-z]* || $t == --[A-Za-z]* ]] && print -r -- ${t%%[^-A-Za-z0-9]*}
    done
}

# parsed <text>: the options its zparseopts calls take, one per line.
parsed() {
    local l spec
    for l in ${(f)${1//\\$'\n'/ }}; do
        [[ $l == *zparseopts*' -- '* ]] || continue
        l=${${l#*' -- '}%%'||'*}
        for spec in ${=l}; do
            print -r -- -${spec%%[=:+]*}
        done
    done
}

# toplevel <file>: its code outside `_x_…() { … }` function definitions.
toplevel() {
    awk '/^_x_[a-z0-9_]*\(\) *\{/ { if ($0 !~ /\}[ \t]*$/) skip = 1; next }
         !skip { print }
         /^\}/ { skip = 0 }' $1
}

# labels <code>: the patterns of its last `case` block, the one its last
# `esac` closes, one per line ("eth|ethz", "*", …).
labels() {
    local -a lines=("${(@f)1}")
    local -i i start=0 end=0 indent=-1
    local lead
    for (( i = $#lines; i >= 1; i-- )); do
        if (( ! end )) && [[ ${lines[i]} == [[:space:]]#esac* ]]; then
            end=i
            lead=${lines[i]%%esac*}
        elif (( end )) && [[ ${lines[i]} == "${lead}case "* ]]; then
            start=i
            break
        fi
    done
    (( start )) || return 0
    local l label='[[:space:]]#[^[:space:]()#][^()]#[)]*'
    for l in ${lines[start+1,end-1]}; do
        [[ $l == $~label ]] || continue
        lead=${l%%[^[:space:]]*}
        (( indent < 0 )) && indent=$#lead
        (( $#lead == indent )) || continue
        print -r -- ${${l##[[:space:]]#}%%\)*}
    done
}

# Commands at position 2: every one, and help.
probe
for line in help ${(k)X_DESCRIPTIONS}; do
    (( ${offered[(Ie)$line]} )) || fail "x <TAB> doesn't offer '$line'"
done

local c p f sub block body help
local -i i
local -a cmds recs paths pa kids kid_descs kid_aliases opts valued docopts recsyn forms
local bare pure
cmds=(${${(f)"$(print -l $fns/x_*(N:t))"}#x_})
for f in $fns/_x_*_complete(N:t); do
    c=${${f#_x_}%_complete}
    (( ${cmds[(Ie)$c]} )) || fail "$f completes 'x $c', which doesn't exist"
done

for c in $cmds; do
    f=$fns/x_$c
    [[ -n ${X_DESCRIPTIONS[$c]} && ${X_DESCRIPTIONS[$c]} != TODO* ]] ||
        fail "x $c: no '## description' line"
    grep -q '_x_usage[^_]' $f &&
        fail "x $c: calls _x_usage; its help is its Usage block (_x_help)"
    grep -Eq '\(-h\|--help' $f && ! grep -q 'h=f_help' $f &&
        fail "x $c: handles -h/--help itself; x does that from the Usage block"

    block=$(_x_usage_block $c)
    [[ ${${(f)block}[1]} == " Usage: x $c"(| *) ]] ||
        fail "x $c: no shape on its Usage line ('# Usage: x $c …')"
    for line in ${(M)${(f)block}:#   x *}; do
        [[ $line == "   x $c"(| *) ]] || fail "x $c: Usage line names another command: '${line#   }'"
    done
    recs=(${(f)"$(_x_synopses $c)"})
    if (( ! $#recs )); then
        fail "x $c: no '# Usage:' block with '#   x $c …' lines"
        continue
    fi

    paths=()
    for line in $recs; do
        pa=(${=line%%$'\t'*})
        for (( i = 1; i <= $#pa; i++ )); do
            (( ${paths[(Ie)${pa[1,i]}]} )) || paths+=("${pa[1,i]}")
        done
    done

    for p in $paths; do
        pa=(${=p})
        _x_usage_info $pa

        # help, three ways (four for the command itself), all the same
        run $pa --help
        help=$out
        (( rc == 0 )) || fail "x $p --help: status $rc"
        [[ ${${(f)out}[1]} == Usage:* && $out == *"x $p"([[:space:]|]*|) ]] ||
            fail "x $p --help: no usage on stdout"
        [[ -z $err ]] || fail "x $p --help: stderr: ${${(f)err}[1]}"
        [[ -z $log ]] || fail "x $p --help: ${${(f)log}[1]}"
        forms=("$pa -h" "help $pa")
        (( $#pa == 1 )) && forms+=("$c help")
        for line in $forms; do
            run ${=line}
            (( rc == 0 )) && [[ $out == $help && -z $err && -z $log ]] ||
                fail "x $line: not the same as x $p --help"
        done

        # a missing or an unknown subcommand
        if (( $#kids && ! bare )); then
            run $pa
            (( rc == 1 )) && [[ -z $out && $err == *Usage:* && -z $log ]] ||
                fail "x $p: no subcommand should show help on stderr, status 1 (got $rc${log:+, ${${(f)log}[1]}})"
        fi
        if (( $#kids && pure )); then
            run $pa no-such-sub
            (( rc == 1 )) && [[ -z $out && $err == *no-such-sub* && -z $log ]] ||
                fail "x $p no-such-sub: should fail before running anything (got $rc${log:+, ${${(f)log}[1]}})"
        fi

        # what the Usage block documents for $p: the arguments of its synopses
        # (recsyn), their options and those on their indented lines, and for
        # the command itself its option lines ("   -k keyid    …")
        docopts=() recsyn=()
        local -i keep=0 j
        local -a sw cp
        for line in ${(f)block}; do
            if [[ $line == ' Usage: x '* ]]; then       # the shape: the command's own
                keep=0
                (( $#pa == 1 )) || continue
                sw=(${=${line# Usage: }})
                recsyn+=("${sw[3,-1]}")
                docopts+=(${(f)"$(options "${sw[3,-1]}")"})
            elif [[ $line == '   x '* ]]; then
                sw=(${=${${line#   }%%  *}})
                cp=()
                for (( j = 2; j <= $#sw; j++ )); do
                    [[ ${sw[j]} == [a-z][a-z0-9-]#(\|[a-z][a-z0-9-]#)# ]] || break
                    cp+=${sw[j]%%\|*}
                done
                keep=0
                if [[ "$cp" == "$p" ]]; then
                    keep=1
                    recsyn+=("${sw[j,-1]}")
                    docopts+=(${(f)"$(options "${sw[j,-1]}")"})
                fi
            elif [[ $line == '    '* ]]; then         # a synopsis's indented lines
                (( keep )) && docopts+=(${(f)"$(options $line)"})
            else
                keep=0
                (( $#pa == 1 )) && [[ $line == '   -'[A-Za-z-]* ]] &&
                    docopts+=(${(f)"$(options ${${line#   }%% *})"})
            fi
        done
        docopts=(${(u)docopts:#(-h|--help)})

        # completion
        probe $pa
        for line in $kids; do
            (( ${offered[(Ie)$line]} )) || fail "x $p <TAB>: doesn't offer '$line'"
        done
        for line in $docopts; do
            (( ${copts[(Ie)$line]} )) || fail "x $p <TAB>: doesn't complete $line"
        done
        if (( ! $#kids )) && [[ ${(j: :)recsyn} == *('<'|'['[^-])* ]] && (( ! $#acts )); then
            fail "x $p <TAB>: completes nothing for its arguments"
        fi

        # the code: options it parses, subcommands it dispatches
        if (( $#pa == 1 )); then
            body=$(toplevel $f)
        else
            body=$(sed -n "/^_x_${(j:_:)pa}() {/,/^}/p" $f)
        fi
        if [[ -n $body ]]; then
            for line in ${(f)"$(parsed $body)"}; do
                [[ $line == -* ]] || continue
                [[ $line == (-h|--help) ]] && continue
                (( ${docopts[(Ie)$line]} )) || fail "x $p: parses $line, which its Usage lines don't show"
            done
        fi
        if (( $#kids && pure )) && [[ -n $body ]]; then
            local -a seen=() alts
            for line in ${(f)"$(labels $body)"}; do
                [[ $line == ('*'|'""') ]] && continue
                alts=(${(s:|:)line})
                sub=${alts[1]}
                if (( ! ${kids[(Ie)$sub]} )); then
                    fail "x $p: dispatches '$line', which isn't a documented subcommand"
                    continue
                fi
                seen+=$sub
                local -a want_alts=($sub ${${(M)kid_aliases:#*=$sub}%=*})
                [[ ${(oj:|:)alts} == ${(oj:|:)want_alts} ]] ||
                    fail "x $p: dispatches '$line', but its Usage says '${(j:|:)want_alts}'"
            done
            for sub in $kids; do
                (( ${seen[(Ie)$sub]} )) || fail "x $p: its Usage has '$sub', its dispatch doesn't"
            done
        fi
    done
    print -r -- "checked x $c (${(j:, :)paths})"
done

if (( $#failures )); then
    print -u2 -l -- "" "${#failures} discoverability problem(s):" "  "${^failures}
    exit 1
fi
print "discoverability ok"
