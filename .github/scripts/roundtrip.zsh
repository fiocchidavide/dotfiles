#!/usr/bin/env zsh
# Seal a small tree with x seal, then verify and extract it with x unseal and
# compare. Exercises tar, zstd, Padmé padding (zstd skippable frames), age
# and xstream.py end to end, with a passphrase on stdin (no 1Password).
#   zsh -f .github/scripts/roundtrip.zsh
emulate -L zsh
setopt err_exit pipe_fail

repo=${0:A:h:h:h}
compdef() {}                      # x.zsh registers completion; no compinit here
source $repo/x/.config/x/x.zsh

work=$(mktemp -d)
trap 'rm -rf -- $work' EXIT
mkdir -p $work/src/sub $work/dst
print hello > $work/src/a.txt
head -c 300000 /dev/urandom > $work/src/sub/b.bin
: > $work/src/empty

pass=correct-horse-battery-staple
x kdf --selftest

print -r -- $pass | x seal -q -p - --name roundtrip --meta $work/meta.json \
    -o $work/out.age $work/src >/dev/null
[[ $(jq -r .padded $work/meta.json) == true ]]

print -r -- $pass | x unseal -q -p - --check $(jq -r .tar.sha256 $work/meta.json) $work/out.age
if print -r -- wrong | x unseal -q -p - --check $work/out.age >/dev/null 2>&1; then
    print -u2 "a wrong passphrase verified"
    exit 1
fi

print -r -- $pass | x unseal -q -p - -C $work/dst $work/out.age >/dev/null
diff -r $work/src $work/dst/src
print "roundtrip ok"
