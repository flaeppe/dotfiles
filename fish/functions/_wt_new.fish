# Create a worktree and make it usable rather than merely checked out.
#
#   wt new <name> [<branch>]
#
# <branch> defaults to <name>. An existing branch is checked out, a remote one is tracked,
# and anything else is created off the default branch -- fetched first, because a worktree
# started from a stale base is something you discover an hour later.
#
# Lands in `.worktrees/<name>`: inside the repository, where one ignore entry covers every
# worktree and nothing has to be resolved to tell a worktree from a clone sitting beside it.
#
# Leaves the shell in the new worktree, since making one is never the thing you wanted.

set -l name $argv[1]
if test -z "$name"
    echo "Usage: wt new <name> [<branch>]"
    return 1
end
set -l branch $argv[2]
test -z "$branch"; and set branch $name

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "wt new: not inside a git repository"
    return 1
end
# The main checkout even when invoked from a linked worktree, so worktrees stay siblings of
# each other rather than nesting inside whichever one happened to be current.
set -l root (dirname $common)
set -l tree "$root/.worktrees/$name"

if test -e $tree
    echo "wt new: $tree already exists"
    return 1
end

# Everything, not just the base: whether <branch> exists on the remote is about to be tested,
# and the answer has to be current or a colleague's branch gets shadowed by a new local one
# started from the wrong place. Prunes as it goes, which is what keeps `wt` honest.
echo "wt new: fetching origin"
git -C $root fetch -q origin; or return 1

set -l base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
if test -z "$base"
    git -C $root remote set-head origin -a >/dev/null
    set base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
end
if test -z "$base"
    echo "wt new: cannot tell which branch origin defaults to"
    return 1
end

if git -C $root show-ref --verify --quiet "refs/heads/$branch"
    echo "wt new: checking out $branch"
    git -C $root worktree add -q $tree $branch; or return 1
else if git -C $root show-ref --verify --quiet "refs/remotes/origin/$branch"
    echo "wt new: tracking origin/$branch"
    git -C $root worktree add -q --track -b $branch $tree "origin/$branch"; or return 1
else
    echo "wt new: branching $branch off $base"
    git -C $root worktree add -q -b $branch $tree $base; or return 1
end

# The same preparation a review worktree gets, and the same per-repository `.review/setup`
# hook: copying the gitignored config, linking dependency trees and materialising a toolchain
# is one problem, not one per surface.
_review_prepare_tree $root $tree worktree

cd $tree
echo "wt new: $name on $branch"
