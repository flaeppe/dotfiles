# Set up a two-worktree review session for a GitHub PR. Both worktrees are always
# created, but only the review one gets an editor tab by default -- pass --stack for
# the second. See docs/pr-review.md for what the two worktrees are for.
#
#   .worktrees/review/<pr>/head    detached at the PR head; markers only, never commits
#   .worktrees/review/<pr>/stack   branch review-suggestions/<pr>-<round>; code only
#
# Re-running against the same PR reuses existing worktrees, so a session is resumable
# after closing the editor.
#
#   review <pr> [--stack] [--no-tab]   start or resume a session; --stack also opens
#                                       the stack tab; --no-tab creates the worktrees
#                                       and stops there -- no kitty tab, no editor --
#                                       and prints the review worktree's path as the
#                                       last line of stdout, for a caller with no tab
#                                       to watch to `cd` into
#   review skim [<pr>]      the read-only surface: browse PRs across the org, one worktree
#   review list             every session in this repo, live or retired
#   review retire <pr>      archive a session and take its worktrees down
#   review post <pr>        post .review/post.json as one PR review; see `_review_post --help`
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
    case post
        _review_post $argv[2..]
        return $status
end

# --stack opens a second tab on the stack worktree, in addition to the review one.
# The worktree itself is always created either way -- see the tab-opening block
# below for why only the tab is conditional. --no-tab skips that whole block,
# for a caller with no tab to land the result in.
set -l stack 0
set -l no_tab 0
set -l pr_arg
for arg in $argv
    if test "$arg" = --stack
        set stack 1
    else if test "$arg" = --no-tab
        set no_tab 1
    else
        set -q pr_arg[1]
        or set pr_arg $arg
    end
end

if test -z "$pr_arg"
    echo "Usage: review <pr-number|url> [--stack] [--no-tab] | review skim [<pr-number|url>] | review list | review retire <pr-number> | review post <pr-number>"
    return 1
end

set -l ref (_review_pr_ref $pr_arg)
or return 1
set -l fields (string split \t -- $ref)
if test (count $fields) -eq 2
    # The ref named another repository -- hand off to that clone rather than running
    # git commands against this one.
    set -l handoff "review $fields[2]"
    if test $stack -eq 1
        set handoff "$handoff --stack"
    end
    fish -c "cd $fields[1]; and $handoff"
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

# --no-tab is for a caller with nobody watching a tab: the worktrees and
# session.json above are the whole deliverable, so stop here rather than reach
# for kitty at all. The worktree path on its own last line is the handoff --
# a caller reads it off stdout and cd's there.
if test $no_tab -eq 1
    echo "review $pr: $title"
    echo $review_tree
    return 0
end

# The base the editor's diff surfaces measure against, as a commit -- the merge base
# already computed above, which is against the PR's declared base branch rather than the
# default branch. That distinction is the whole point for a stacked PR, whose base is the
# branch below it.
#
# REVIEW_BASE_DIR names the worktree the base was minted for, and is what stops it
# spreading. Both variables are inherited by everything the editor spawns -- a `:terminal`
# that cd's to another worktree of this repository and starts an editor there would
# otherwise measure that worktree against this PR's base, silently, because the commit
# resolves in a shared object database. One string per worktree rather than one shared:
# the value differs, which is the entire point.
set -l base_env "set -x REVIEW_BASE $merge_base; and set -x REVIEW_BASE_DIR"
set -l review_launch "$base_env $review_tree; and direnv export fish | source; and nvim -c Review"
set -l stack_launch "$base_env $stack_tree; and direnv export fish | source; and nvim -c Review"

set -l kitty_socket (_review_kitty_socket)
if test -z "$kitty_socket"
    echo "review: no kitty control socket found -- is remote control on?"
    return 1
end

# One tab per worktree: curating findings and building suggestions are different
# worktrees, so they need separate cwd, LSP root and tag file rather than one
# editor straddling both. The editor first in each tab, then a shell beside it,
# kept out of focus so landing on either tab lands on the editor.
#
# The stack tab is opt-in (--stack): most sessions never touch the stack, and its
# worktree -- created above regardless, so a session already open can still be
# handed --stack later -- sits ready without a tab on it until asked for.
kitty @ --to $kitty_socket launch --type=tab --tab-title "review $pr" \
    --cwd $review_tree fish -i -c $review_launch >/dev/null
or begin
    echo "review: could not open a kitty tab (is remote control allowed?)"
    return 1
end
kitty @ --to $kitty_socket launch --location=hsplit --dont-take-focus --cwd $review_tree >/dev/null 2>&1

if test $stack -eq 1
    kitty @ --to $kitty_socket launch --type=tab --tab-title "stack $pr" \
        --cwd $stack_tree fish -i -c $stack_launch >/dev/null
    kitty @ --to $kitty_socket launch --location=hsplit --dont-take-focus --cwd $stack_tree >/dev/null 2>&1
end

echo "review $pr: $title"
if test $stack -eq 0
    echo "             stack pane not opened -- reopen this session with: review $pr --stack"
end
