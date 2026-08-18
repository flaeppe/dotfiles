# The worktrees `wt rm` will consider, as fish completion candidates.
#
#   _wt_candidates
#
# Tab-separated name and description, which is the format `complete -a` reads. The repo's
# own checkout and its review sessions are left out, being the two things `wt rm` refuses,
# and a completion offering a name only to produce an error is worse than one that is quiet.
# The skim surface and agent worktrees are offered: they are removable like any other, and
# leaving them out made the ones that most need clearing the ones that could not be named.
#
# Named by the same path the listing prints, relative to the directory holding the
# repositories. `wt rm` also takes a bare directory name, but a completion that suggests one
# spelling while the listing shows another reads as though the two disagree about which
# worktree is meant.

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
or return
set -l root (dirname $common)
set -l workspace (dirname $root)

for record in (_wt_trees $root)
    set -l fields (string split \t -- $record)
    test $fields[1] = $root; and continue
    set -l owner (_wt_owner $fields[1])
    test "$owner" = review; and continue

    set -l label $fields[3]
    test -z "$label"; and set label "detached at "(string sub -l 8 -- $fields[2])
    printf '%s\t%s\n' (string replace "$workspace/" '' -- $fields[1]) $label
end
