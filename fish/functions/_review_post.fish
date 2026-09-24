# Posts one GitHub PR review from `.review/post.json`. Deterministic and LLM-free: this
# reads and posts, it never decides what a review says. Composing `.review/post.json` --
# from the REVIEW[n] markers, `.review/summary.md` and whatever else `.review/` holds --
# is a session's job; see docs/pr-review.md.
#
#   review post <pr> [--dry-run]
#
# `post.json` is `{"event": "APPROVE"|"COMMENT"|"REQUEST_CHANGES", "body": "...",
# "comments": [{"path", "line", "side", "body"}, ...]}`.
#
# Each comment's `path`+`line` is checked against the PR's own diff, this session's base
# to this worktree's own HEAD (never the PR's current tip, which may have moved past what
# this session reviewed) -- the same two revisions GitHub diffs, measured locally rather
# than by fetching the PR's files. GitHub rejects the *entire* review if one comment lands
# outside a diff hunk, so an unanchorable comment is moved into the body under its own
# heading instead -- never dropped, never silently skipped.
#
# `--dry-run` prints exactly what would post and posts nothing.

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: review post <pr-number> [--dry-run]"
    echo ""
    echo "Posts .review/post.json (event, body, comments[]) as one GitHub PR review."
    echo "A comment whose path:line isn't in the PR's diff moves into the body instead"
    echo "of being dropped. --dry-run prints what would post and posts nothing."
    return 0
end

set -l pr
set -l dry_run 0
for arg in $argv
    if test "$arg" = --dry-run
        set dry_run 1
    else if string match -qr '^\d+$' -- $arg
        set pr $arg
    end
end
if test -z "$pr"
    echo "Usage: review post <pr-number> [--dry-run]"
    return 1
end

# Resolve the main checkout rather than the current one, so this runs the same whether
# invoked from the review worktree, the stack worktree, or the main checkout.
set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review post: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l review_tree "$root/.worktrees/review/$pr/head"
set -l post_json "$review_tree/.review/post.json"
set -l session_json "$review_tree/.review/session.json"

if not test -d $review_tree
    echo "review post: no review worktree for $pr -- run: review $pr"
    return 1
end
if not test -f $session_json
    echo "review post: no $session_json -- this worktree was never a review session"
    return 1
end
if not test -f $post_json
    echo "review post: no $post_json -- compose it first, then run this"
    return 1
end
if not jq empty $post_json 2>/dev/null
    echo "review post: $post_json is not valid JSON"
    return 1
end

set -l event (jq -r '.event // empty' $post_json)
if not contains -- $event APPROVE COMMENT REQUEST_CHANGES
    echo "review post: .event in $post_json must be APPROVE, COMMENT or REQUEST_CHANGES -- got '$event'"
    return 1
end

set -l draft_body (jq -r '.body // ""' $post_json | string collect)
set -l all_comments (jq -c '.comments // [] | .[]' $post_json)
if test -z "$draft_body"; and test (count $all_comments) -eq 0
    echo "review post: empty body and no comments in $post_json -- nothing to post"
    return 1
end

# Only RIGHT is ever valid: a marker sits on the code as it reads after the change, so
# every comment it produces anchors to the new side of the diff. A comment claiming LEFT
# is a compose bug, not a case to handle -- fail loud rather than mis-anchor it.
for comment in $all_comments
    set -l side (printf '%s' $comment | jq -r '.side // "RIGHT"')
    if test "$side" != RIGHT
        set -l path (printf '%s' $comment | jq -r '.path')
        echo "review post: $path has side '$side' in $post_json -- only RIGHT is valid"
        return 1
    end
end

set -l base (jq -r '.merge_base // empty' $session_json)
if test -z "$base"
    echo "review post: $session_json has no merge_base"
    return 1
end
set -l head (git -C $review_tree rev-parse HEAD)

# The remote rather than `gh repo view`: the owner is already in the URL, so reading it
# locally costs no request.
set -l origin (git -C $review_tree remote get-url origin 2>/dev/null)
set -l slug_match (string match -r 'github\.com[:/]([^/]+)/(.+?)(\.git)?$' -- $origin)
if test (count $slug_match) -lt 3
    echo "review post: origin is not a GitHub remote: $origin"
    return 1
end
set -l slug "$slug_match[2]/$slug_match[3]"

set -l anchored
set -l orphaned
for comment in $all_comments
    set -l path (printf '%s' $comment | jq -r '.path')
    set -l line (printf '%s' $comment | jq -r '.line')
    set -l body (printf '%s' $comment | jq -r '.body' | string collect)

    set -l ok 0
    for hunk in (git -C $review_tree diff --unified=0 $base $head -- $path | string match -r '^@@ .* @@')
        set -l m (string match -r -- '@@ -\d+,?\d* \+(\d+),?(\d*) @@' $hunk)
        test (count $m) -lt 3; and continue
        set -l new_start $m[2]
        set -l new_count $m[3]
        test -z "$new_count"; and set new_count 1
        if test $new_count -gt 0; and test $line -ge $new_start; and test $line -lt (math "$new_start + $new_count")
            set ok 1
            break
        end
    end

    if test $ok -eq 1
        set -a anchored (jq -nc --arg path $path --argjson line $line --arg body $body \
            '{path: $path, line: $line, side: "RIGHT", body: $body}')
    else
        set -a orphaned "- `$path:$line` — "$body
    end
end

set -l body_chunks $draft_body
if test (count $orphaned) -gt 0
    set -a body_chunks "" "" "---" "" "Not on a line this pull request's diff shows:" "" $orphaned
end
set -l final_body (string join \n -- $body_chunks | string collect)

set -l joined_comments (string join , -- $anchored)
set -l comments_json "[$joined_comments]"

if test $dry_run -eq 1
    echo "review post $pr --dry-run: $event on $slug#$pr at "(string sub -l 7 -- $head)
    echo ""
    echo (count $anchored)" inline comment(s):"
    for comment in $anchored
        set -l path (printf '%s' $comment | jq -r '.path')
        set -l line (printf '%s' $comment | jq -r '.line')
        set -l preview (printf '%s' $comment | jq -r '.body' | head -1)
        echo "  $path:$line  $preview"
    end
    if test (count $orphaned) -gt 0
        echo ""
        echo (count $orphaned)" comment(s) moved into the body -- their line isn't in the PR's diff:"
        for line in $orphaned
            echo "  $line"
        end
    end
    echo ""
    echo "--- body ---"
    echo $final_body
    echo "--- end body ---"
    echo ""
    echo "dry run -- nothing posted"
    return 0
end

set -l payload (jq -nc --arg commit_id $head --arg event $event --arg body $final_body --argjson comments $comments_json \
    '{commit_id: $commit_id, event: $event, body: $body, comments: $comments}')

set -l result (printf '%s' $payload | gh api --method POST "repos/$slug/pulls/$pr/reviews" --input - --jq '.html_url' 2>&1)
if test $status -ne 0
    echo "review post: GitHub rejected the review, nothing was posted --"
    echo (string join \n -- $result)
    return 1
end

echo "review post: $event posted on $slug#$pr — "(count $anchored)" inline comment(s), "(count $orphaned)" folded into the body"
echo "  $result"
