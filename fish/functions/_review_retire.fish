# Retire a review session: archive what it produced, then take its worktrees down.
#
# A session's reasoning -- the summary, the harvested findings, the assembled bodies -- lives
# inside the review worktree, while its code lives on the stack branch. Removing the worktrees
# therefore destroys the reasoning and keeps the code, which is the wrong half. So everything
# is copied out first, the stack included as a patch: with that patch archived, deleting the
# branch later stops being irreversible.
#
# The stack branch itself is kept. It is the only place the suggestions exist as commits, and
# whether they still matter is a judgement this cannot make -- `review list` reports it, and
# `git branch -D` ends it.

set -l pr
for arg in $argv
    if string match -qr '^\d+$' -- $arg
        set pr $arg
        break
    end
end
if test -z "$pr"
    echo "Usage: review retire <pr-number> [--force]"
    return 1
end

set -l forced 0
if contains -- --force $argv
    set forced 1
end

# Resolve the main checkout rather than the current one: this is meant to be runnable from
# anywhere in the repo, and inside a linked worktree `--show-toplevel` would name the worktree.
set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review retire: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l repo (basename $root)
set -l review_tree "$root/.worktrees/review/$pr/head"
set -l stack_tree "$root/.worktrees/review/$pr/stack"

set -l state_home $XDG_STATE_HOME
if test -z "$state_home"
    set state_home "$HOME/.local/state"
end
set -l archive_root "$state_home/review/$repo"

if not test -d $review_tree; and not test -d $stack_tree
    echo "review $pr: no worktrees -- this session is already retired"
    for ref in (git -C $root for-each-ref --format='%(refname:short)' "refs/heads/review-suggestions/$pr" "refs/heads/review-suggestions/$pr-*")
        echo "           branch still here: $ref"
    end
    for dir in $archive_root/$pr $archive_root/$pr-*
        test -d $dir; and echo "           archived: $dir"
    end
    return 0
end

# Removing the directory the shell is sitting in leaves it in a deleted cwd, and git refuses
# halfway through, so the session ends up half torn down.
for tree in $review_tree $stack_tree
    if string match -q "$tree*" -- $PWD
        echo "review retire: you are standing in $tree"
        echo "               cd out of the session first"
        return 1
    end
end

# A responding socket means an editor is open on a worktree about to be deleted. Existence
# alone proves nothing -- a killed editor leaves its socket file behind.
for socket in /tmp/nvim-review-$repo-$pr.sock /tmp/nvim-stack-$repo-$pr.sock
    if test -e $socket; and nvim --server $socket --remote-expr '1' >/dev/null 2>&1
        if test $forced -eq 0
            echo "review retire: an editor is still open on this session"
            echo "               $socket is live -- close it, or pass --force"
            return 1
        end
    end
end

set -l stack_branch
if test -d $stack_tree
    set stack_branch (git -C $stack_tree rev-parse --abbrev-ref HEAD)

    # Uncommitted work in the stack tree is a suggestion mid-flight: it was never accepted, so
    # it exists nowhere else and no archive step below would catch it.
    set -l in_flight (git -C $stack_tree status --porcelain)
    if test -n "$in_flight"; and test $forced -eq 0
        echo "review retire: the stack worktree has uncommitted work in "(count $in_flight)" path(s)"
        echo "               accept it with :ReviewAccept, discard it, or pass --force"
        return 1
    end
end

# The commit the worktrees are on, which bounds the stack's commits. Never `pr/<pr>`: a later
# `review` run force-fetches that ref to the upstream tip, so it can point past this session.
set -l base
if test -d $review_tree
    set base (git -C $review_tree rev-parse HEAD)
else if test -f "$stack_tree/.review/session.json"
    set base (jq -r .pr_head "$stack_tree/.review/session.json")
end

set -l archive "$archive_root/"(basename $stack_branch)
mkdir -p $archive

echo "review $pr: archiving to $archive"

# Copy rather than move, and only what exists: a retire re-run after a partial teardown then
# leaves already-archived artifacts alone instead of replacing them with nothing.
for name in session.json summary.md findings.md order.json notes out
    if test -e "$review_tree/.review/$name"
        cp -R "$review_tree/.review/$name" "$archive/$name"
    end
end

if test -d $review_tree
    set -l markers (git -C $review_tree status --porcelain)
    if test -n "$markers"
        git -C $review_tree diff >"$archive/markers.diff"
    end
end

set -l commits 0
if test -n "$stack_branch"; and test -n "$base"
    set commits (git -C $root rev-list --count "$base..$stack_branch")
    if test $commits -gt 0
        git -C $root format-patch --stdout "$base..$stack_branch" >"$archive/stack.patch"
    end
else if test -n "$stack_branch"
    echo "review $pr: WARNING could not determine the session's base commit,"
    echo "            so the stack was not archived as a patch. $stack_branch still holds it."
end

# Only what actually landed here gets a row. A phase the session never reached leaves no
# file, and naming one anyway would send a later reader looking for something that was never
# written.
set -l manifest "$archive/MANIFEST.md"
printf '# review %s\n\n' $pr >$manifest
printf 'Retired from `%s`. Branch `%s`, %s commit(s) over `%s`.\n\n' \
    $repo "$stack_branch" $commits (string sub -l 9 -- "$base") >>$manifest
printf '| File | Contents |\n|---|---|\n' >>$manifest
for name in session.json summary.md findings.md order.json notes out markers.diff stack.patch
    test -e "$archive/$name"; or continue
    switch $name
        case session.json
            printf '| `session.json` | the session as it stood: PR, base, both worktrees |\n' >>$manifest
        case summary.md
            printf '| `summary.md` | the review as prose |\n' >>$manifest
        case findings.md
            printf '| `findings.md` | the harvested findings, with their sites |\n' >>$manifest
        case order.json
            printf '| `order.json` | the reading order through the PR |\n' >>$manifest
        case notes
            printf '| `notes/` | per-finding implementation records; folded into the commits |\n' >>$manifest
        case out
            printf '| `out/` | the assembled bodies and the publish plan |\n' >>$manifest
        case markers.diff
            printf '| `markers.diff` | the in-code markers, as they were left |\n' >>$manifest
        case stack.patch
            printf '| `stack.patch` | the accepted suggestions, as commits |\n' >>$manifest
    end
end

if test -f "$archive/stack.patch"
    printf '\nRestore the suggestions onto any commit:\n\n' >>$manifest
    printf '```sh\ngit checkout -b %s <base>\ngit am %s/stack.patch\n```\n' \
        "$stack_branch" $archive >>$manifest
end
if test -f "$archive/markers.diff"
    printf '\nRestore the markers into a checkout of `%s`:\n\n' (string sub -l 9 -- "$base") >>$manifest
    printf '```sh\ngit apply %s/markers.diff\n```\n' $archive >>$manifest
end

# `--force` unconditionally: the review worktree is dirty by design, since markers are never
# committed. What protects real work is the in-flight gate above, not this flag.
for tree in $review_tree $stack_tree
    if test -d $tree
        git -C $root worktree remove --force $tree
    end
end
git -C $root worktree prune
# Each rmdir refuses while anything is left, so a second session in this repo keeps its own
# directories and only the last one out empties the tree.
rmdir "$root/.worktrees/review/$pr" "$root/.worktrees/review" "$root/.worktrees" 2>/dev/null

# Re-fetchable: GitHub keeps `pull/<pr>/head` after the PR merges and after the author deletes
# their branch, so dropping the local ref loses nothing.
if git -C $root rev-parse --verify -q "pr/$pr" >/dev/null
    git -C $root branch -q -D "pr/$pr"
end

for socket in /tmp/nvim-review-$repo-$pr.sock /tmp/nvim-stack-$repo-$pr.sock
    test -e $socket; and rm -f $socket
end

echo "review $pr: retired"
echo "  archived   $archive"
if test -n "$stack_branch"
    echo "  kept       $stack_branch — $commits commit(s)"
    echo "             delete with:  git branch -D $stack_branch"
end
echo "  removed    both worktrees, pr/$pr, editor sockets"
echo "  note       the session's Kitty tabs now point at deleted directories"
