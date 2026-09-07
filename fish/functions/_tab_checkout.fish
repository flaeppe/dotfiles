# The checkout a directory sits in, as the tab bar labels it: the repository
# name, and the worktree name after it when the directory is not the
# repository's own checkout.
#
#   _tab_checkout <directory>
#
# Empty for a directory in no repository at all, which is a legitimate answer
# for a tab -- the caller decides what to show instead.
#
# The repository name comes from the *common* git dir's parent, not from the
# checkout's own path: a linked worktree lives at an arbitrary path and only
# that parent names the repository it belongs to.

set -l dir $argv[1]
if test -z "$dir"; or not test -d "$dir"
    return 0
end

set -l common (git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    return 0
end
set -l repo (basename (dirname $common))

set -l top (git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
set -l tree (basename "$top")
if test -z "$top"; or test "$tree" = "$repo"
    echo (string replace -r '^\.' '' -- $repo)
    return 0
end

echo (string replace -r '^\.' '' -- $repo)/$tree
