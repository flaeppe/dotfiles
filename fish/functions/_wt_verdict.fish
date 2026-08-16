# What a worktree's git state says about removing it.
#
#   _wt_verdict <root> <path> <sha> <branch> <base> <upstream> <track>
#
# One tab-separated line: <state> <dirty> <ahead> <behind> <push>
#
# States, in the order they are tested -- the first that holds wins, so a worktree that is
# both merged and dirty reports dirty:
#
#   orphaned  detached and holding commits no ref contains; removing it destroys them
#   dirty     uncommitted files, which exist in this directory and nowhere else
#   stranded  commits on a branch that was never pushed
#   merged    nothing the base branch does not already have
#   gone      the branch was deleted upstream, which is what a squash merge leaves behind
#   active    work in progress, and on the remote
#
# `upstream` and `track` are passed in rather than read here so a caller listing a hundred
# worktrees can batch one `for-each-ref` across the whole repository instead of forking per
# worktree.
#
# One function rather than a rule in the listing and a second in the remover: the listing
# calling a worktree removable while the remover refuses it is the failure worth designing
# against.

set -l root $argv[1]
set -l path $argv[2]
set -l sha $argv[3]
set -l branch $argv[4]
set -l base $argv[5]
set -l upstream $argv[6]
set -l track $argv[7]

# Left is what the base has and this does not, right is what only this has. Only the right
# side is work: a worktree zero commits ahead holds nothing that would be lost.
set -l counts (string split \t -- (git -C $root rev-list --left-right --count "$base...$sha" 2>/dev/null))
set -l behind $counts[1]
set -l ahead $counts[2]
test -z "$ahead"; and set ahead 0
test -z "$behind"; and set behind 0

set -l dirty (git -C $path status --porcelain 2>/dev/null | count)

set -l push
set -l stranded 0
if test -z "$branch"
    set push -
else if test -z "$upstream"
    # Never pushed at all, so everything past the base exists only in this repository.
    set push local
    set stranded $ahead
else if test "$track" = '[gone]'
    set push gone
else if set -l m (string match -r 'ahead (\d+)' -- $track)
    set stranded $m[2]
    set push "↑$m[2]"
else if set -l m (string match -r 'behind (\d+)' -- $track)
    set push "↓$m[2]"
else
    set push ok
end

set -l state active
if test -z "$branch"; and test $ahead -gt 0; and test (git -C $root for-each-ref --contains $sha --count=1 refs/heads refs/remotes | count) -eq 0
    set state orphaned
else if test $dirty -gt 0
    set state dirty
else if test $stranded -gt 0
    set state stranded
else if test $ahead -eq 0
    set state merged
else if test "$push" = gone
    set state gone
end

printf '%s\t%s\t%s\t%s\t%s\n' $state $dirty $ahead $behind $push
