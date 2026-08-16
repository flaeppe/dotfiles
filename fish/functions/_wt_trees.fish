# Every worktree of a repository, one record per line.
#
#   _wt_trees <repository-root>
#
# Tab-separated: <path> <head-sha> <branch, empty when detached> <locked/prunable flags>
#
# `git worktree list --porcelain` is a record format rather than a table -- one field per
# line, entries begun by `worktree`, absent fields simply missing -- so anything wanting a
# row has to reassemble one. This is that, once, rather than in each caller.

set -l root $argv[1]

set -l paths
set -l heads
set -l branches
set -l flags
for line in (git -C $root worktree list --porcelain)
    switch (string split -f1 ' ' -- $line)
        case worktree
            set -a paths (string sub -s 10 -- $line)
            set -a heads ""
            set -a branches ""
            set -a flags ""
        case HEAD
            set heads[-1] (string sub -s 6 -- $line)
        case branch
            set branches[-1] (string replace refs/heads/ '' -- (string sub -s 8 -- $line))
        case locked prunable
            set flags[-1] (string trim -- "$flags[-1] "(string split -f1 ' ' -- $line))
    end
end

for i in (seq (count $paths))
    printf '%s\t%s\t%s\t%s\n' $paths[$i] $heads[$i] $branches[$i] $flags[$i]
end
