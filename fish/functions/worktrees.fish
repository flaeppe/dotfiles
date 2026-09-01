# An overview of every worktree and what it would cost to delete one.
#
#   wt                    worktrees of this repository
#   wt --all              every repository under the workspace root (this one's parent)
#   wt --size             measure each one on disk (slow: it walks every file)
#   wt new <name> [<branch>]   create one in .worktrees/ and prepare it
#   wt rm [--force] <name>...  remove ones that hold nothing, and their branches
#
# `git worktree list` says where the worktrees are and nothing about whether they still hold
# anything, so they accumulate: there is never a moment where one visibly becomes garbage.
# The columns are picked to answer only that. Unfinished work can hide in exactly three
# places -- commits the base branch does not have (AHEAD), uncommitted files (DIRTY), and
# commits never pushed (PUSH) -- and a worktree empty in all three is finished, whatever it
# looks like.
#
# AHEAD, BEHIND and the gone marker are read from remote-tracking refs, so they are only as
# current as the last fetch. The header dates every repository for that reason; against a
# stale fetch this whole listing understates how finished things are.

switch "$argv[1]"
    case new
        _wt_new $argv[2..]
        return $status
    case rm
        _wt_rm $argv[2..]
        return $status
    case retire
        # Real word, wrong command: `review retire` archives a session before dropping its
        # trees, and a plain worktree has nothing to archive, so the two never merge into one.
        echo "wt: no 'retire' here -- try `wt rm` (review sessions: `review retire`)" >&2
        return 1
    case '*'
        # Anything left is either a flag (argparse below owns those, including its own
        # errors on an unknown one) or a verb nobody defined. A bare word is not an error
        # to argparse -- it is left in $argv and ignored -- so refusing it here is the only
        # thing standing between a typo and a successful-looking no-op.
        if test -n "$argv[1]"; and not string match -q -- '-*' "$argv[1]"
            echo "wt: unrecognised verb '$argv[1]' -- try `wt new`, `wt rm`, or `wt --help`" >&2
            return 1
        end
end

argparse a/all s/size h/help -- $argv
or return 1

if set -q _flag_help
    echo "Usage: wt [--all] [--size] | wt new <name> [<branch>] | wt rm [--force] <name>..."
    echo
    echo "  wt                          worktrees of this repository"
    echo "  wt --all                    every repository under the workspace root"
    echo "  wt --size                   measure each one on disk (slow)"
    echo "  wt new <name> [<branch>]    create one in .worktrees/ and prepare it"
    echo "  wt rm [--force] <name>...   remove ones that hold nothing, and their branches"
    return 0
end

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "wt: not inside a git repository"
    return 1
end

# Worktrees sit both inside the repository and beside it, so paths are shown relative to the
# directory holding the repositories rather than to any one checkout.
set -l workspace (dirname (dirname $common))

# Passed on as a value rather than read again, because `_wt_repo` is a function and argparse's
# flags are local to this one.
set -l measure
set -q _flag_size; and set measure yes

if not set -q _flag_all
    _wt_repo $common $workspace $measure
    return $status
end

set -l commons
for dir in $workspace/*/
    set -l c (git -C $dir rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    or continue
    set -a commons $c
end
if test -z "$commons"
    echo "wt: no repositories under $workspace"
    return 1
end

# A repository whose only worktree is its own checkout has nothing to maintain, and at this
# scale those are the majority; listing them would bury the ones that do.
set -l single 0
for c in (printf '%s\n' $commons | sort -u)
    if test (git -C (dirname $c) worktree list --porcelain | string match -r '^worktree ' | count) -le 1
        set single (math $single + 1)
        continue
    end
    _wt_repo $c $workspace $measure
end

printf '%s%d repositories, %d with only their own checkout (not shown)%s\n' \
    (set_color brblack) (count (printf '%s\n' $commons | sort -u)) $single (set_color normal)
