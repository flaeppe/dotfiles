# Move a review session's head tree onto the PR's current head, uncommitted markers
# carried, and show what changed since the commit last reviewed.
#
#   _review_refresh <pr>
#
# Reached from `review refresh <pr>`. The stack tree is not touched: its suggestions are
# commits on the head the session was started from, and moving it would mean rebasing them.
#
# The previous head is kept in `.review/previous_head`, which `review <pr>` never rewrites,
# so the range stays reproducible:  git diff $(cat .review/previous_head) HEAD

set -l pr $argv[1]
if not string match -qr '^\d+$' -- "$pr"
    echo "Usage: review refresh <pr-number>"
    return 1
end

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review refresh: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l review_tree "$root/.worktrees/review/$pr/head"
set -l session_json "$review_tree/.review/session.json"
if not test -f $session_json
    echo "review refresh: no session for PR $pr -- start one with: review $pr"
    return 1
end

set -l base_branch (jq -r .base_branch $session_json)
# --no-prune: with `fetch.prune` set, git deletes `pr/<pr>` again whenever the fetch finds it
# already present, because the refspec's source `pull/<pr>/head` never matches the remote's
# `refs/pull/<pr>/head` in the prune check.
git -C $root fetch -q --force --no-prune origin "pull/$pr/head:refs/heads/pr/$pr"; or return 1
git -C $root fetch -q origin $base_branch; or return 1

# The tree's own HEAD, not the ref as it stood before the fetch: a refresh that was refused
# leaves `pr/<pr>` already moved, and the next attempt must still see a difference.
set -l old (git -C $review_tree rev-parse HEAD)
set -l new (git -C $root rev-parse "pr/$pr")
if test "$old" = "$new"
    echo "review $pr: the PR has not moved -- still at "(string sub -l 9 -- $old)
    return 0
end

set -l merge_base (git -C $root merge-base "origin/$base_branch" $new)
or return 1

# A plain checkout: git refuses, naming the files, when it would overwrite an uncommitted
# marker, and leaves the tree as it was.
git -C $review_tree checkout -q --detach $new
or begin
    echo "review refresh: $review_tree is unchanged, still at "(string sub -l 9 -- $old)
    return 1
end

echo $old >"$review_tree/.review/previous_head"
jq --arg head $new --arg base $merge_base \
    '.pr_head = $head | .pr_tip = $head | .merge_base = $base' $session_json >"$session_json.tmp"
and mv "$session_json.tmp" $session_json

echo "review $pr: "(string sub -l 9 -- $old)" -> "(string sub -l 9 -- $new)", markers kept"
git -C $review_tree log --format='  %h %s' --reverse $old..$new
git -C $review_tree diff --stat $old $new

# Same remote call `review skim` uses to retarget an open editor.
set -l socket (jq -r '.review_socket // empty' $session_json)
if test -n "$socket"; and test -S $socket; and nvim --server $socket --remote-expr \
        "luaeval('vim.schedule(function() vim.cmd(\"DiffviewOpen $old..$new\") end)')" >/dev/null 2>&1
    echo "review $pr: opened $old..$new in the editor"
else
    echo "review $pr: no editor on this session -- open it with  :DiffviewOpen $old..$new"
end
