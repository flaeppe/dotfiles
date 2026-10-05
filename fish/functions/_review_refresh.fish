# Move a review session's head tree onto the PR's current head, uncommitted markers
# carried, and show what changed since the commit last reviewed.
#
#   _review_refresh <pr>
#
# Reached from `review refresh <pr>`. The stack tree is not touched: its suggestions are
# commits on the head the session was started from, and moving it would mean rebasing them.
#
# Markers are carried by lifting them out of the files, moving the tree, and putting each
# back where its code line now is -- or, when that line cannot be found, tagged STALE for
# the reviewer to place. See `_review_markers_lift` and `_review_markers_reapply`.
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

# A refresh that stopped between lifting the markers and putting them back leaves the
# markers only in `.review/anchors.json`; finish or undo it before anything else moves.
set -l anchors_json "$review_tree/.review/anchors.json"
if test -f $anchors_json; and test (jq -r .applied $anchors_json) = false
    set -l here (git -C $review_tree rev-parse HEAD)
    if test "$here" = (jq -r .to $anchors_json)
        echo "review $pr: finishing the marker re-application an earlier refresh left half-way"
        _review_markers_reapply $review_tree
        return $status
    else if test "$here" = (jq -r .from $anchors_json)
        echo "review $pr: an earlier refresh stopped before moving the tree -- putting its markers back"
        _review_markers_lift --undo $review_tree
    else
        echo "review refresh: $anchors_json holds markers that were never put back, and the tree is at"
        echo "  $here, not the commit it names -- the markers are in that file, the files as they were in"
        echo "  $review_tree/.review/refresh-backup/"
        return 1
    end
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

# With the markers out of the way a plain checkout only refuses for what else is uncommitted
# in a file the new commits change -- naming the files, tree untouched -- or for an
# untracked file in the way. The markers go back where they were.
_review_markers_lift $review_tree $old $new; or return 1
git -C $review_tree checkout -q --detach $new
or begin
    _review_markers_lift --undo $review_tree
    echo "review refresh: $review_tree is unchanged, still at "(string sub -l 9 -- $old)", markers back where they were"
    return 1
end

echo $old >"$review_tree/.review/previous_head"
jq --arg head $new --arg base $merge_base \
    '.pr_head = $head | .pr_tip = $head | .merge_base = $base' $session_json >"$session_json.tmp"
and mv "$session_json.tmp" $session_json

set -l marker_report (_review_markers_reapply $review_tree)
set -l reapplied $status

echo "review $pr: "(string sub -l 9 -- $old)" -> "(string sub -l 9 -- $new)
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

# Last, so the line that says what is left to do is the one the reviewer reads.
test $reapplied -eq 0; or echo "review $pr: WARNING putting the markers back failed -- they are in $anchors_json; run: review refresh $pr"
if test (count $marker_report) -gt 0
    printf '%s\n' $marker_report
end
