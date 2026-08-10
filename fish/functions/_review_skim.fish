# The read-only reviewing surface: one worktree per repository, standing ready, that
# moves from PR to PR from inside the editor.
#
#   .worktrees/skim    detached, never on a branch, never committed to
#
#   review skim          open the surface where it last was
#   review skim <pr>     open it on a PR
#
# See docs/pr-review.md for why this is a third surface rather than a mode of a session.
#
# One per repository, not one per PR, because it holds nothing worth keeping: findings
# leave as a comment pasted into GitHub, so the next PR can overwrite it. That is the
# whole difference from a session, and it is what makes switching cost nothing.
#
# Deliberately outside `.worktrees/review/`, whose children are all PR numbers to
# `review list`.

if test -n "$argv[1]"; and not string match -qr '^\d+$' -- "$argv[1]"
    echo "review skim: '$argv[1]' is not a PR number"
    return 1
end
set -l pr $argv[1]

# The main checkout even when invoked from a linked worktree, so `review skim` from
# inside a session reaches the one surface rather than nesting another.
set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review skim: not inside a git repository"
    return 1
end
set -l root (dirname $common)
set -l repo (basename $root)
set -l tree "$root/.worktrees/skim"

# One editor per repository, addressable: the PR list spans the whole organisation, so
# picking a PR in another repository has to reach that repository's surface. With a
# socket it retargets the window already open there instead of opening a second one.
set -l socket "/tmp/nvim-skim-$repo.sock"

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
# editor rewrites it on every switch.
if not test -f "$tree/.review/skim.json"
    printf '{\n  "repo": "%s",\n  "pr": null\n}\n' $repo >"$tree/.review/skim.json"
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
        kitty @ --to $kitty_socket focus-tab --match "title:^skim $repo\$" >/dev/null 2>&1
    end
    return 0
end

set -l entry PrList
if test -n "$pr"
    set entry "PrDiff $pr"
end
set -l launch "direnv export fish | source; and nvim --listen $socket -c \"$entry\""

# One tab, unlike a session's two: there is no stack to build here.
if test -n "$kitty_socket"
    # The editor first, then a shell beside it. The second launch lands in the tab the
    # first one created, which kitty has made active by then.
    kitty @ --to $kitty_socket launch --type=tab --tab-title "skim $repo" \
        --cwd $tree fish -i -c $launch >/dev/null
    or begin
        echo "review skim: could not open a kitty tab (is remote control allowed?)"
        return 1
    end
    kitty @ --to $kitty_socket launch --location=hsplit --cwd $tree >/dev/null 2>&1
    echo "review skim: $repo — <Leader>hl lists PRs across the org, ctrl-r opens a full session"
    return 0
end

# No kitty listening to ask, so an OS window is the only option left.
set -l session_file "$tree/.review/kitty-session"
printf 'os_window_name skim %s\nfocus_os_window\n\n' $repo >$session_file
printf 'new_tab skim %s\nlayout tall\n' $repo >>$session_file
printf 'launch --location=hsplit --cwd %s fish -i -c \'%s\'\n' $tree $launch >>$session_file
printf 'launch --location=hsplit --cwd %s\n' $tree >>$session_file

echo "review skim: $repo — <Leader>hl lists PRs across the org, ctrl-r opens a full session"
new-session $session_file
