# Remove worktrees that are finished, and the branches they were finished with.
#
#   wt rm [--force] <name>...
#
# The refusals are the point, and the test is only ever whether something would be lost.
# `git worktree remove` deletes the directory, and for uncommitted files and never-pushed
# commits that directory is the only place they are, so a worktree holding either is named
# rather than removed. One whose work is on the remote is removed without ceremony, finished
# or not -- it can be had back. --force is for when losing it is the answer you wanted.
#
# Worktrees belonging to `review` are refused outright and not force-removable: retiring a
# session archives its findings first, and taking the tree down behind its back loses them.
#
# The branch goes with the worktree when the worktree was removable because the work landed
# -- otherwise every finished branch outlives its directory and the branch list becomes the
# same problem one layer down.

argparse f/force -- $argv
or return 1

if test -z "$argv[1]"
    echo "Usage: wt rm [--force] <name>..."
    return 1
end

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "wt rm: not inside a git repository"
    return 1
end
set -l root (dirname $common)

set -l base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
if test -z "$base"
    set base (git -C $root rev-parse --abbrev-ref HEAD)
end

set -l records (_wt_trees $root)
set -l failed 0

set -l force_arg
set -q _flag_force; and set force_arg --force

for target in $argv
    # Accepts what the listing prints, a bare directory name, or any trailing part of the
    # path. Ambiguity is reported rather than guessed at, since guessing wrong here deletes
    # the wrong directory.
    set -l matches
    for record in $records
        set -l path (string split -f1 \t -- $record)
        if test "$path" = "$target"; or test (basename $path) = "$target"; or string match -q "*/$target" -- $path
            set -a matches $path
        end
    end
    if test (count $matches) -eq 0
        echo "wt rm: no worktree matching '$target'"
        set failed 1
        continue
    end
    if test (count $matches) -gt 1
        echo "wt rm: '$target' matches more than one worktree:"
        printf '         %s\n' $matches
        set failed 1
        continue
    end

    set -l path $matches[1]
    if test $path = $root
        echo "wt rm: $target is the repository's own checkout"
        set failed 1
        continue
    end

    # Only a review session, and only because retiring one archives its findings first --
    # taking its trees down here loses them. The skim surface and an agent's worktree hold
    # nothing another command is keeping for them, so what protects those is the same test
    # that protects everything else: whether anything would be lost.
    set -l owner (_wt_owner $path)
    if test "$owner" = review
        # The PR number is the directory holding head/ and stack/.
        echo "wt rm: $target is a review session — `review retire "(basename (dirname $path))"` archives it first"
        set failed 1
        continue
    end

    set -l record (string match -e -- "$path"\t $records)
    set -l fields (string split \t -- $record[1])
    set -l sha $fields[2]
    set -l branch $fields[3]

    set -l upstream
    set -l track
    if test -n "$branch"
        set -l info (git -C $root for-each-ref --format='%(upstream:short)|%(upstream:track)' "refs/heads/$branch")
        set -l parts (string split '|' -- $info[1])
        set upstream $parts[1]
        set track $parts[2]
    end

    set -l v (string split \t -- (_wt_verdict $root $path $sha "$branch" $base "$upstream" "$track"))
    set -l state $v[1]
    set -l dirty $v[2]
    set -l ahead $v[3]

    if not set -q _flag_force
        switch $state
            case dirty
                echo "wt rm: $target has $dirty uncommitted file(s) — commit them, or --force"
                set failed 1
                continue
            case stranded
                echo "wt rm: $target has $ahead commit(s) that were never pushed — push them, or --force"
                set failed 1
                continue
            case orphaned
                echo "wt rm: $target is detached with $ahead commit(s) no branch points at"
                echo "         they are unreachable once it is gone — branch them, or --force"
                set failed 1
                continue
        end
    end

    # Standing inside what is about to be deleted leaves the shell in a directory that no
    # longer exists, where every later command fails for reasons that look unrelated.
    if string match -q "$path/*" -- "$PWD/"
        cd $root
    end

    # Go writes its module cache read-only, directories included, and direnv puts one inside
    # the worktree. Nothing can unlink an entry from a directory it cannot write, so deletion
    # fails partway -- and `git worktree remove` deregisters the worktree anyway, leaving a
    # stub directory belonging to nothing and a branch that never got cleaned up. Making the
    # tree writable first is what avoids that; it is about to be deleted either way.
    # Symlinks are not followed, so a dependency tree linked from the main checkout is safe.
    chmod -R u+w $path 2>/dev/null

    if not git -C $root worktree remove $force_arg $path
        echo "wt rm: git would not remove $target — $path is still there"
        set failed 1
        continue
    end
    echo "wt rm: removed $target"
    test "$owner" = skim; and echo "       `review skim` builds it again when it is next wanted"

    # Only when the work landed. A branch kept past a --force removal is the whole reason
    # the removal needed forcing.
    if test -z "$branch"
        continue
    end
    switch $state
        case merged
            git -C $root branch -q -d $branch
            and echo "       deleted branch $branch"
        case gone
            # -D, because a squash merge leaves the original commits unreachable from the base
            # and -d refuses them forever. The sha is printed so the reflog can undo this.
            git -C $root branch -q -D $branch
            and echo "       deleted branch $branch ("(string sub -l 8 -- $sha)", deleted upstream)"
        case '*'
            echo "       kept branch $branch"
    end
end

return $failed
