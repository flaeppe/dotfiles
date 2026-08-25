# The read-only reviewing surface: one worktree per repository, standing ready, that
# moves from PR to PR from inside the editor.
#
#   .worktrees/skim    detached, never on a branch, never committed to
#
#   review skim          open the surface where it last was
#   review skim <pr>     open it on a PR
#
# <pr> is a bare number in this repository, or a pull-request URL naming another one --
# own PRs included, so a link pasted out of a browser or Slack works exactly like a
# number typed by hand. See `_review_pr_ref`.
#
# See docs/pr-review.md for why this is a third surface rather than a mode of a session.
#
# One per repository, not one per PR, because it holds nothing worth keeping: findings
# leave as a review posted from the editor, so the next PR can overwrite it. That is the
# whole difference from a session, and it is what makes switching cost nothing.
#
# Deliberately outside `.worktrees/review/`, whose children are all PR numbers to
# `review list`.

set -l pr
if test -n "$argv[1]"
    set -l ref (_review_pr_ref $argv[1])
    or return 1
    set -l fields (string split \t -- $ref)
    if test (count $fields) -eq 2
        # The ref named another repository -- hand off to that clone's own skim surface
        # rather than running git commands against this one.
        fish -c "cd $fields[1]; and review skim $fields[2]"
        return $status
    end
    set pr $fields[1]
end

# The main checkout even when invoked from a linked worktree, so `review skim` from
# inside a session reaches the one surface rather than nesting another.
set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review skim: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l repo (basename $root)

# The author's seat: a PR whose branch is checked out in one of this repository's
# worktrees is own work, and the surface to open is that worktree. The diff machinery is
# identical -- :PrDiff signs against the merge base without touching a checkout that is
# already on the PR's branch -- but edits land on the live branch instead of a
# read-only copy.
set -l own_tree ""
set -l base_branch ""
if test -n "$pr"
    set -l meta (gh pr view $pr --json headRefName,baseRefName \
        --jq '[.headRefName, .baseRefName] | @tsv' 2>/dev/null)
    if test -n "$meta"
        set -l pr_fields (string split \t -- $meta)
        set -l head_branch $pr_fields[1]
        set base_branch $pr_fields[2]
        set own_tree (git worktree list --porcelain | \
            awk -v ref="branch refs/heads/$head_branch" '/^worktree /{wt=substr($0,10)} $0==ref{print wt; exit}')
    end
end

set -l tree "$root/.worktrees/skim"
set -l title "skim $repo"
# One editor per repository, addressable: the PR list spans the whole organisation, so
# picking a PR in another repository has to reach that repository's surface. With a
# socket it retargets the window already open there instead of opening a second one.
# Own worktrees get a socket each: retargeting a PR into the wrong worktree's editor
# would `gh pr checkout` over work in progress.
set -l socket "/tmp/nvim-skim-$repo.sock"
if test -n "$own_tree"
    set -l wt_name (basename $own_tree)
    set tree $own_tree
    set title "own $repo $wt_name"
    set socket "/tmp/nvim-own-$repo-$wt_name.sock"
end

if test -z "$own_tree"
    if not test -d $tree
        echo "review skim: creating the skim worktree"
        # Detached at whatever the main checkout is on, which is only a placeholder until the
        # first PR is picked. Never a branch -- the reviewer is frequently the author, and a
        # branch already checked out in the main worktree cannot be checked out here too.
        git worktree add -q --detach $tree HEAD; or return 1
    end

    _review_prepare_tree $root $tree skim

    # Presence of this file is what tells the editor it is standing on the skim surface, and
    # therefore that loading a PR means a detached checkout here rather than `gh pr checkout`
    # in place. It carries the current PR so the surface survives closing the editor; the
    # editor rewrites it on every switch. An own worktree must never get one: it is not the
    # skim surface, and the marker file would make loading another PR there detach it.
    if not test -f "$tree/.review/skim.json"
        printf '{\n  "repo": "%s",\n  "pr": null\n}\n' $repo >"$tree/.review/skim.json"
    end
end

# An editor already listening is the one to reuse -- a second window on the same worktree
# would fight it over the checkout.
# The kitty already running, so moving between repositories costs a tab rather than an OS
# window. Its control socket is per-instance (`listen_on` gets `-<pid>` appended), so the
# environment's own value is preferred and a lone listening socket is the fallback.
set -l kitty_socket $KITTY_LISTEN_ON
if test -z "$kitty_socket"
    # `find` rather than a glob, which errors in fish when nothing matches.
    set -l listening (find /tmp -maxdepth 1 -name 'mykitty-*' -type s 2>/dev/null)
    if test (count $listening) -eq 1
        set kitty_socket "unix:$listening[1]"
    end
end

if test -S $socket
    if test -n "$pr"
        # An expression, not `--remote-send`: this surface normally sits in a picker, and
        # keystrokes sent to an editor in one land in the picker's prompt rather than
        # running as a command. Scheduled so the load happens on the main loop instead of
        # inside the RPC handler.
        nvim --server $socket --remote-expr \
            "luaeval('vim.schedule(function() vim.cmd(\"PrDiff $pr\") end)')" >/dev/null 2>&1
        or begin
            echo "review skim: $repo has a stale socket -- close that editor and retry"
            return 1
        end
        echo "review skim: sent PR $pr to the editor already open on $repo"
    else
        echo "review skim: $repo is already open"
    end
    # Bring it forward, since the point of asking was to look at it.
    if test -n "$kitty_socket"
        kitty @ --to $kitty_socket focus-tab --match "title:^$title\$" >/dev/null 2>&1
    end
    return 0
end

set -l entry PrList
if test -n "$pr"
    set entry "PrDiff $pr"
end
set -l launch "direnv export fish | source; and nvim --listen $socket -c \"$entry\""

# The base the editor's diff surfaces measure against, as a commit. The PR's declared
# base branch, never the default branch: a stacked PR sits on the branch below it, and
# diffing that against master shows the whole stack instead of this PR.
#
# Only computable here on an own worktree, which is already standing on the PR's head.
# The skim worktree is not on the PR until the editor checks it out, so there `:PrDiff`
# exports this itself once it knows the head.
if test -n "$own_tree"; and test -n "$base_branch"
    git -C $tree fetch -q origin $base_branch 2>/dev/null
    set -l review_base (git -C $tree merge-base HEAD "origin/$base_branch" 2>/dev/null)
    if test -n "$review_base"
        set launch "set -x REVIEW_BASE $review_base; and $launch"
    end
end

# One tab, unlike a session's two: there is no stack to build here.
if test -n "$kitty_socket"
    # The editor first, then a shell beside it. The second launch lands in the tab the
    # first one created, which kitty has made active by then.
    kitty @ --to $kitty_socket launch --type=tab --tab-title "$title" \
        --cwd $tree fish -i -c $launch >/dev/null
    or begin
        echo "review skim: could not open a kitty tab (is remote control allowed?)"
        return 1
    end
    kitty @ --to $kitty_socket launch --location=hsplit --cwd $tree >/dev/null 2>&1
    echo "review skim: $repo — <Leader>hl lists PRs across the org, ctrl-r opens a full session"
    return 0
end

# No kitty listening to ask, so an OS window is the only option left. The session file
# stays out of an own worktree, whose git status it would pollute.
set -l session_file "$tree/.review/kitty-session"
if test -n "$own_tree"
    set session_file (mktemp -t kitty-own-session)
end
printf 'os_window_name %s\nfocus_os_window\n\n' $title >$session_file
printf 'new_tab %s\nlayout tall\n' $title >>$session_file
printf 'launch --location=hsplit --cwd %s fish -i -c \'%s\'\n' $tree $launch >>$session_file
printf 'launch --location=hsplit --cwd %s\n' $tree >>$session_file

echo "review skim: $repo — <Leader>hl lists PRs across the org, ctrl-r opens a full session"
new-session $session_file
