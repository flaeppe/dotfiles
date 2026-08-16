# The worktrees `wt rm` will consider, as fish completion candidates.
#
#   _wt_candidates
#
# Tab-separated name and description, which is the format `complete -a` reads. The repo's
# own checkout and the trees `review` owns are left out, because `wt rm` refuses them and a
# completion that offers a name only to produce an error is worse than one that stays quiet.
#
# Named by directory alone where that is unique, which it nearly always is; the longer form
# is a tie-break rather than the default, because it is not something worth typing otherwise.

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
or return
set -l root (dirname $common)

set -l paths
set -l labels
for record in (_wt_trees $root)
    set -l fields (string split \t -- $record)
    test $fields[1] = $root; and continue
    set -l owner (_wt_owner $fields[1])
    test -n "$owner"; and continue

    set -a paths $fields[1]
    if test -n "$fields[3]"
        set -a labels $fields[3]
    else
        set -a labels "detached at "(string sub -l 8 -- $fields[2])
    end
end
test (count $paths) -eq 0; and return

set -l names (path basename $paths)
for i in (seq (count $paths))
    set -l name $names[$i]
    if test (count (string match -- $name $names)) -gt 1
        set name (string replace "$root/" '' -- $paths[$i])
    end
    printf '%s\t%s\n' $name $labels[$i]
end
