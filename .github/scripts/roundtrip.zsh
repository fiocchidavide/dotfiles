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

# Without --name the archive name is random: 26 base32 characters.
mkdir $work/dst2
print -r -- $pass | x seal -q -p - -o $work/out2.age $work/src >/dev/null
print -r -- $pass | x unseal -q -p - -C $work/dst2 $work/out2.age >/dev/null
diff -r $work/src $work/dst2/src
rand=$(_x_rand_b32 26)
[[ ${#rand} == 26 && $rand != *[^a-z2-7]* ]]

# gzip, which never pads (what x vault share uses), and zstd with --no-pad.
mkdir $work/dst3
print -r -- $pass | x seal -q -p - -z gzip --meta $work/gz.json -o $work/gz.age $work/src >/dev/null
[[ $(jq -r .padded $work/gz.json) == false ]]
print -r -- $pass | x unseal -q -p - -z gzip -C $work/dst3 $work/gz.age >/dev/null
diff -r $work/src $work/dst3/src
print -r -- $pass | x seal -q -p - --no-pad --meta $work/np.json -o $work/np.age $work/src >/dev/null
[[ $(jq -r .padded $work/np.json) == false ]]

# -O: the tar stream on stdout.
list=$(print -r -- $pass | x unseal -q -p - -O $work/out.age | tar -tf -)
(( ${${(f)list}[(Ie)src/sub/b.bin]} ))

# A name that's taken: the contents go into out.unsealed, an ordinary folder.
kept=$(print -r -- $pass | x unseal -q -p - -C $work/dst $work/out.age)
[[ $kept == $work/dst/out.unsealed ]]
diff -r $work/src $kept/src
[[ $(stat -f %Lp $kept) == $(printf '%o' $(( 8#777 & ~8#$(umask) ))) ]]

# A level the compressor doesn't have stops before anything is written.
if print -r -- $pass | x seal -q -p - -z gzip -L 19 -o $work/bad.age $work/src >/dev/null 2>&1; then
    print -u2 "gzip -L 19 was accepted"
    exit 1
fi
[[ ! -e $work/bad.age ]]
print "roundtrip ok"
