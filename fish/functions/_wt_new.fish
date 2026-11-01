# Create a worktree and make it usable rather than merely checked out.
#
#   wt new <name> [<branch>]
#   wt new <name> <remote>/<ref>
#
# <branch> defaults to <name>. An existing branch is checked out, a remote one is tracked,
# and anything else is created off the default branch -- fetched first, because a worktree
# started from a stale base is something you discover an hour later.
#
# A commit sha in the <branch> slot is likewise a place to start from. Ceiling: a sha-shaped
# word that is not a commit in this repository (an unfetched sha) is taken as a branch name.
#
# A remote-tracking ref in the <branch> slot is where to start from, not a branch to make: the
# new branch is called <name> and begins at that ref. A local branch named `origin/main` would
# shadow the remote-tracking one in every `git checkout`, so no spelling of the arguments
# creates one.
#
# That fetch needs an `origin` to ask. Without one -- no remote at all, or a remote under
# some other name -- there is nothing to fetch and no origin/HEAD to read, so the default
# branch falls back to whatever the main checkout currently has out, and a line says so. A
# fetch that fails for a transient reason (offline, auth) degrades the same way instead of
# aborting, so one flaky network call doesn't cost the whole command.
#
# Lands in `.worktrees/<name>`: inside the repository, where one ignore entry covers every
# worktree and nothing has to be resolved to tell a worktree from a clone sitting beside it.
#
# Leaves the shell in the new worktree, since making one is never the thing you wanted.

argparse -n 'wt new' h/help -- $argv
or return 1

if set -q _flag_help
    echo "Usage: wt new <name> [<branch>]"
    echo "       wt new <name> <remote>/<ref>"
    echo
    echo "  <branch>        checked out if it exists, tracked if origin has it, else created"
    echo "                  off the default branch"
    echo "  <remote>/<ref>  a remote-tracking ref: <name> is created starting from it"
    echo "  <sha>           a commit: <name> is created starting from it"
    return 0
end

set -l name $argv[1]
if test -z "$name"
    echo "Usage: wt new <name> [<branch>]"
    return 1
end

# `--` lets a leading dash through argparse, and git would then read the name as an option.
for arg in $argv[1..2]
    if string match -q -- '-*' $arg
        echo "wt new: '$arg' starts with '-' -- names and branches cannot"
        return 1
    end
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

# Decided by the remote's name rather than by whether the ref exists yet, because a remote
# branch the fetch below is about to bring in would otherwise be taken for a new local one.
set -l remotes (git -C $root remote)
set -l start
if string match -rq -- '^(?<remote>[^/]+)/.' "$argv[2]"; and contains -- $remote $remotes
    set start $argv[2]
    set branch $name
end
if test -z "$start"; and string match -qr -- '^[0-9a-f]{7,40}$' "$argv[2]"
    and not git -C $root show-ref --verify --quiet "refs/heads/$argv[2]"
    and not git -C $root show-ref --verify --quiet "refs/remotes/origin/$argv[2]"
    and git -C $root rev-parse --verify --quiet "$argv[2]^{commit}" >/dev/null
    set start $argv[2]
    set branch $name
end
if string match -rq -- '^(?<remote>[^/]+)/.' "$branch"; and contains -- $remote $remotes
    echo "wt new: '$branch' is a remote-tracking ref, so a local branch of that name would shadow it -- name the worktree something else"
    return 1
end
if test -n "$start"
    if git -C $root show-ref --verify --quiet "refs/heads/$branch"; or git -C $root show-ref --verify --quiet "refs/remotes/origin/$branch"
        echo "wt new: branch $branch already exists, so it cannot be started from $start"
        return 1
    end
end

# Everything, not just the base: whether <branch> exists on the remote is about to be tested,
# and the answer has to be current or a colleague's branch gets shadowed by a new local one
# started from the wrong place. Prunes as it goes, which is what keeps `wt` honest.
set -l base $start
if git -C $root remote get-url origin >/dev/null 2>&1
    echo "wt new: fetching origin"
    if not git -C $root fetch -q origin
        echo "wt new: WARNING fetch origin failed, base may be stale"
    end

    if test -z "$base"
        set base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
    end
    if test -z "$base"
        git -C $root remote set-head origin -a >/dev/null 2>&1
        set base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
    end

    if test -n "$base"
        # $base is a remote-tracking ref, so a worktree based on it silently lacks
        # whatever the same-named local branch has that origin doesn't -- commits
        # never pushed. Warned about rather than based on the local ref instead:
        # switching to local would just as silently pick up whatever half-finished
        # state that branch happens to be in, which is its own way of handing an
        # agent a base nobody chose on purpose.
        set -l local_base (string replace -r '^origin/' '' -- $base)
        if git -C $root show-ref --verify --quiet "refs/heads/$local_base"
            set -l ahead (git -C $root rev-list --count "$base..$local_base" 2>/dev/null)
            if test -n "$ahead"; and test "$ahead" -gt 0
                echo "wt new: WARNING local $local_base is $ahead commit(s) ahead of $base -- this worktree won't have them"
            end
        end
    end
end

if test -z "$base"
    # No `origin` to ask (missing, or a remote under some other name), or a fetch that
    # failed before origin/HEAD was ever cached locally. The main checkout is the closest
    # thing left to a source of truth: worktrees exist precisely so work happens off to the
    # side and the main checkout stays put on the default branch, so whatever it currently
    # has out is taken to be that branch. Gets it wrong if the main checkout itself is
    # mid-feature-branch or detached at the moment `wt new` runs.
    set base (git -C $root symbolic-ref -q --short HEAD)
    if test -z "$base"
        echo "wt new: cannot tell which branch to base off -- no origin/HEAD and the main checkout is detached"
        return 1
    end
    echo "wt new: no origin/HEAD, branching off local $base"
end

# `worktree add` refuses a branch another worktree has out, with a bare fatal that does not say
# which one; the holder is the place the caller wants.
set -l holder (git -C $root worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '
    /^worktree / { path = substr($0, 10) }
    $0 == ref { print path; exit }')
if test -n "$holder"
    echo "wt new: $branch is already checked out at $holder -- work there, or name another branch"
    return 1
end

if git -C $root show-ref --verify --quiet "refs/heads/$branch"
    echo "wt new: checking out $branch"
    git -C $root worktree add -q $tree $branch; or return 1
else if git -C $root show-ref --verify --quiet "refs/remotes/origin/$branch"
    echo "wt new: tracking origin/$branch"
    git -C $root worktree add -q --track -b $branch $tree "origin/$branch"; or return 1
else
    # --no-track: when $base is a remote-tracking ref, git's default
    # branch.autoSetupMerge would otherwise point the new branch's upstream
    # at $base itself (e.g. origin/master) rather than at a same-named
    # branch that doesn't exist yet. Left alone, that upstream is wrong for
    # every push -- `git push` reports the two names don't match, and the
    # only way past it is a refspec spelling out where to push, on every
    # single push. A no-op when $base is a local branch instead (no remote
    # to fall back to), but harmless there too.
    echo "wt new: branching $branch off $base"
    git -C $root worktree add -q --no-track -b $branch $tree $base; or return 1
end

# A worktree that came up on anything but $branch is the whole failure mode this
# guards against, so it is checked rather than assumed. `symbolic-ref --short HEAD`
# alone does not catch every way that can happen: on a case-insensitive filesystem
# (APFS's default), requesting a branch that differs only in case from one that
# already exists -- e.g. "Main" when "main" is checked out at $root -- resolves to
# the SAME ref file, so the new worktree checks out $root's branch under an alias.
# `symbolic-ref` and `branch --show-current` both echo back "$branch" faithfully
# in that case; the tell is that $branch never shows up, byte for byte, among the
# refs git's own ref-store enumerates. A commit made there lands on $root's branch,
# not a new one -- which is exactly what was reported: an agent committing onto
# local main while believing it was on a feature branch.
set -l actual (git -C $tree symbolic-ref -q --short HEAD)
if test "$actual" != "$branch"; or not contains -- $branch (git -C $root for-each-ref --format='%(refname:short)' refs/heads)
    echo "wt new: FATAL -- $tree came up on '$actual', not a distinct '$branch' -- removing it"
    git -C $root worktree remove --force $tree 2>/dev/null
    return 1
end

# The same preparation a review worktree gets, and the same per-repository `.review/setup`
# hook: copying the gitignored config, linking dependency trees and materialising a toolchain
# is one problem, not one per surface.
_review_prepare_tree $root $tree worktree

cd $tree
echo "wt new: $name on $branch"
