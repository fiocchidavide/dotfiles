#!/usr/bin/env zsh
# What a friend runs for `x vault share`: seal a tree with x seal --random,
# then open it with share/open.sh (which fetches and checks its own age) and
# compare. The tree holds the awkward cases: a read-only folder, a dangling
# symlink and a ..-name; the destination already holds a dangling symlink of
# the same name. No terminal, so open.sh takes its prompts' defaults.
#   zsh -f .github/scripts/open-share.zsh
emulate -L zsh
setopt err_exit pipe_fail

repo=${0:A:h:h:h}
compdef() {}
source $repo/x/.config/x/x.zsh

work=$(mktemp -d)
trap 'chmod -R u+w $work; rm -rf -- $work' EXIT
mkdir -p $work/src/pkg/ro $work/dl $work/dest
print hello > $work/src/pkg/ro/f
print odd > $work/src/pkg/..odd
ln -s /nonexistent $work/src/pkg/dangling
chmod 555 $work/src/pkg/ro
ln -s /nowhere $work/dest/pkg

pass=$(x seal -q --random --name share-test -o $work/dl/share-test.age $work/src/pkg 2>/dev/null | tail -1)
(cd $work/dl && bash $repo/x/.config/x/share/open.sh $pass share-test.age --to $work/dest </dev/null)

diff -r --no-dereference $work/src/pkg $work/dest/pkg
[[ ! -e $work/dl/share-test.age ]]     # the download was removed (default: yes)
print "open-share ok"
