# Every review session this repo has, live or retired.
#
# Retiring a session removes its worktrees, so `git worktree list` stops being able to show
# what reviews exist. What outlives a session is a branch and an archive directory, and neither
# is anywhere you would look. This is where they are.

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review list: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l repo (basename $root)

set -l state_home $XDG_STATE_HOME
if test -z "$state_home"
    set state_home "$HOME/.local/state"
end
set -l archive_root "$state_home/review/$repo"

# A session leaves traces in three places and any one of them can be the last: worktrees until
# it is retired, a branch until the suggestions are dropped, an archive from then on.
set -l prs
for dir in (find "$root/.worktrees/review" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    set -a prs (basename $dir)
end
for ref in (git -C $root for-each-ref --format='%(refname:short)' 'refs/heads/review-suggestions/*')
    set -a prs (string replace -r -- '-\d+$' '' (string replace 'review-suggestions/' '' -- $ref))
end
for dir in (find $archive_root -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    set -a prs (string replace -r -- '-\d+$' '' (basename $dir))
end
if test -z "$prs"
    echo "$repo: no review sessions"
    return 0
end
set prs (printf '%s\n' $prs | sort -un)

echo "$repo — review sessions"
echo

for pr in $prs
    set -l review_tree "$root/.worktrees/review/$pr/head"
    set -l stack_tree "$root/.worktrees/review/$pr/stack"
    set -l live down
    if test -d $review_tree; or test -d $stack_tree
        set live live
    end

    set -l state (gh pr view $pr --json state --jq .state 2>/dev/null)
    if test -z "$state"
        set state unknown
    end

    printf '  %-6s worktrees %-5s · PR %s\n' $pr $live $state

    for ref in (git -C $root for-each-ref --format='%(refname:short)' "refs/heads/review-suggestions/$pr" "refs/heads/review-suggestions/$pr-*")
        set -l archive "$archive_root/"(basename $ref)

        # The base the suggestions were built on. The archived session file is preferred over
        # the live worktree because it is the only source that is still right for a round other
        # than the current one.
        set -l base
        if test -f "$archive/session.json"
            set base (jq -r '.pr_head // empty' "$archive/session.json")
        else if test -d $review_tree
            set base (git -C $review_tree rev-parse HEAD)
        end
        set -l count ?
        if test -n "$base"
            set count (git -C $root rev-list --count "$base..$ref" 2>/dev/null)
        end
        printf '        %-34s %s commit(s)\n' $ref "$count"

        # Whether the suggestions themselves landed cannot be detected: a squash merge leaves
        # their commits unreachable from the base branch, so an ancestry test reads false
        # forever. So this reports the two things it can stand behind -- the reviewed PR is
        # finished, and the patch is on disk -- and leaves the judgement alone.
        if test $live = live
            continue
        end
        if test -f "$archive/stack.patch"
            if contains -- $state MERGED CLOSED
                printf '        safe to delete: git branch -D %s\n' $ref
            end
        else
            printf '        no patch archived — deleting this branch would be irreversible\n'
        end
    end

    for dir in (find $archive_root -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        set -l name (basename $dir)
        if test "$name" = "$pr"; or string match -qr "^$pr-\d+\$" -- $name
            printf '        archive  %s\n' $dir
        end
    end
    echo
end

echo "  review retire <pr>   archive a session and take its worktrees down"
