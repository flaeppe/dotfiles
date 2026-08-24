# Set up a two-worktree review session for a GitHub PR and open an editor on each.
# See docs/pr-review.md for what the two worktrees are for.
#
#   .worktrees/review/<pr>/head    detached at the PR head; markers only, never commits
#   .worktrees/review/<pr>/stack   branch review-suggestions/<pr>-<round>; code only
#
# Re-running against the same PR reuses existing worktrees, so a session is resumable
# after closing the editor.
#
#   review <pr>          start or resume a session
#   review skim [<pr>]   the read-only surface: browse PRs across the org, one worktree
#   review list          every session in this repo, live or retired
#   review retire <pr>   archive a session and take its worktrees down
#
# <pr> is a bare number in this repository, or a pull-request URL naming another one --
# own PRs included, so a link pasted out of a browser or Slack works exactly like a
# number typed by hand. See `_review_pr_ref`.

switch "$argv[1]"
    case list
        _review_list $argv[2..]
        return $status
    case retire
        _review_retire $argv[2..]
        return $status
    case skim
        _review_skim $argv[2..]
        return $status
end

if test -z "$argv[1]"
    echo "Usage: review <pr-number|url> | review skim [<pr-number|url>] | review list | review retire <pr-number>"
    return 1
end

set -l ref (_review_pr_ref $argv[1])
or return 1
set -l fields (string split \t -- $ref)
if test (count $fields) -eq 2
    # The ref named another repository -- hand off to that clone rather than running
    # git commands against this one.
    fish -c "cd $fields[1]; and review $fields[2]"
    return $status
end

set -l pr $fields[1]
set -l root (git rev-parse --show-toplevel 2>/dev/null)
if test -z "$root"
    echo "review: not inside a git repository"
    return 1
end

set -l repo (basename $root)
set -l review_tree "$root/.worktrees/review/$pr/head"
set -l stack_tree "$root/.worktrees/review/$pr/stack"

echo "review $pr: reading PR metadata"
set -l meta (gh pr view $pr --json headRefName,baseRefName,title,url \
    --jq '[.headRefName, .baseRefName, .title, .url] | @tsv' 2>/dev/null)
if test -z "$meta"
    echo "review: could not read PR $pr (is `gh` authenticated for this repo?)"
    return 1
end
set -l fields (string split \t -- $meta)
set -l head_branch $fields[1]
set -l base_branch $fields[2]
set -l title $fields[3]
set -l url $fields[4]

echo "review $pr: fetching pull/$pr/head"
git fetch -q --force origin "pull/$pr/head:refs/heads/pr/$pr"; or return 1
git fetch -q origin "$base_branch"

# The upstream tip, which is not necessarily what this session reviews: the author
# can push while a review is in progress.
set -l pr_tip (git rev-parse "pr/$pr")

# Detached rather than on the pr/<pr> branch: the review worktree must never
# accumulate commits, and a detached HEAD makes that the path of least action.
if not test -d $review_tree
    echo "review $pr: creating review worktree"
    git worktree add -q --detach $review_tree "pr/$pr"; or return 1
end
# Stack branches are numbered per PR, because one PR can be reviewed more than once:
# a round whose suggestions were merged (or abandoned) must not be reopened by the next
# one. The highest existing round is continued only while it still descends from the
# commit this session reviews -- once its suggestions have landed in the PR, or the base
# moved out from under it, that branch belongs to a finished round and the next round
# gets its own number.
#
# An existing stack worktree short-circuits this: that is a session being resumed, and
# its branch is whatever it was checked out on.
if test -d $stack_tree
    set -g stack_branch (git -C $stack_tree rev-parse --abbrev-ref HEAD)
else
    set -l round 0
    for ref in (git for-each-ref --format='%(refname:short)' "refs/heads/review-suggestions/$pr-*")
        set -l n (string replace -r ".*-" "" -- $ref)
        if string match -qr '^\d+$' -- $n; and test $n -gt $round
            set round $n
        end
    end
    set -g stack_branch "review-suggestions/$pr-$round"
    if test $round -gt 0; and git merge-base --is-ancestor "pr/$pr" $stack_branch 2>/dev/null
        echo "review $pr: continuing round $round on $stack_branch"
        git worktree add -q $stack_tree $stack_branch; or return 1
    else
        set round (math $round + 1)
        set -g stack_branch "review-suggestions/$pr-$round"
        echo "review $pr: creating stack worktree on $stack_branch (round $round)"
        git worktree add -q -b $stack_branch $stack_tree "pr/$pr"; or return 1
    end
end

# The commit the worktrees are actually at is the session's base -- never the
# freshly fetched tip. Overwriting it on a re-run would leave every computed range
# pointing at a commit the worktrees are not on, which reads as phantom changes in
# files the review never touched.
set -l pr_head (git -C $review_tree rev-parse HEAD)
set -l merge_base (git merge-base "origin/$base_branch" $pr_head)

if test "$pr_head" != "$pr_tip"
    set -l ahead (git rev-list --count $pr_head..$pr_tip 2>/dev/null)
    echo "review $pr: NOTE the PR has moved on -- $ahead new commit(s) upstream."
    echo "             this session reviews $pr_head"
    echo "             to review the new head:  review retire $pr  then  review $pr"
    echo "             (retiring archives this round's findings and keeps $stack_branch)"
end

for role in review stack
    if test $role = review
        set -f tree $review_tree
    else
        set -f tree $stack_tree
    end
    _review_prepare_tree $root $tree $role $pr
end

# Sockets live in /tmp, never in the worktree: macOS caps unix socket paths at
# ~104 characters and a nested worktree path burns most of that budget.
set -l review_socket "/tmp/nvim-review-$repo-$pr.sock"
set -l stack_socket "/tmp/nvim-stack-$repo-$pr.sock"

for role in review stack
    if test $role = review
        set -f tree $review_tree
    else
        set -f tree $stack_tree
    end
    printf '{\n' >"$tree/.review/session.json"
    printf '  "pr": %s,\n' $pr >>"$tree/.review/session.json"
    printf '  "title": "%s",\n' (string replace -a '"' '\\"' -- $title) >>"$tree/.review/session.json"
    printf '  "url": "%s",\n' $url >>"$tree/.review/session.json"
    printf '  "repo": "%s",\n' $repo >>"$tree/.review/session.json"
    printf '  "role": "%s",\n' $role >>"$tree/.review/session.json"
    printf '  "head_branch": "%s",\n' $head_branch >>"$tree/.review/session.json"
    printf '  "base_branch": "%s",\n' $base_branch >>"$tree/.review/session.json"
    printf '  "pr_head": "%s",\n' $pr_head >>"$tree/.review/session.json"
    printf '  "pr_tip": "%s",\n' $pr_tip >>"$tree/.review/session.json"
    printf '  "merge_base": "%s",\n' $merge_base >>"$tree/.review/session.json"
    printf '  "stack_branch": "%s",\n' $stack_branch >>"$tree/.review/session.json"
    printf '  "review_worktree": "%s",\n' $review_tree >>"$tree/.review/session.json"
    printf '  "stack_worktree": "%s",\n' $stack_tree >>"$tree/.review/session.json"
    printf '  "review_socket": "%s",\n' $review_socket >>"$tree/.review/session.json"
    printf '  "stack_socket": "%s"\n' $stack_socket >>"$tree/.review/session.json"
    printf '}\n' >>"$tree/.review/session.json"
end

# One tab per loop: curating findings and building suggestions are different
# worktrees, so they need separate cwd, LSP root and tag file rather than one
# editor straddling both.
set -l session_file "$review_tree/.review/kitty-session"
printf 'os_window_name review %s\nfocus_os_window\n\n' $pr >$session_file
printf 'new_tab review %s\nlayout tall\n' $pr >>$session_file
printf 'launch --location=hsplit --cwd %s fish -i -c \'direnv export fish | source; and nvim -c Review\'\n' $review_tree >>$session_file
printf 'launch --location=hsplit --cwd %s\n' $review_tree >>$session_file
printf 'focus\n\n' >>$session_file
printf 'new_tab stack %s\nlayout tall\n' $pr >>$session_file
printf 'launch --location=hsplit --cwd %s fish -i -c \'direnv export fish | source; and nvim -c Review\'\n' $stack_tree >>$session_file
printf 'launch --location=hsplit --cwd %s\n' $stack_tree >>$session_file

echo "review $pr: $title"
new-session $session_file
