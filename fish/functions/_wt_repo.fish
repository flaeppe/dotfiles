# One repository's worktrees, oldest first, with the reason each one is or is not finished.
#
#   _wt_repo <git-common-dir> <workspace-root>

set -l common $argv[1]
set -l workspace $argv[2]
set -l root (dirname $common)

# The base every branch is measured against. origin/HEAD is the only place the default branch
# is recorded locally, and it is absent on clones made before it was set, so a repository that
# has never had it resolved falls back to its own checkout.
set -l base (git -C $root symbolic-ref -q --short refs/remotes/origin/HEAD)
if test -z "$base"
    set base (git -C $root rev-parse --abbrev-ref HEAD)
end

# Date, upstream and tracking state for every branch in one call. Asking per worktree instead
# would triple the git invocations for a listing that already spans a hundred of them.
set -l refinfo (git -C $root for-each-ref \
    --format='%(refname:short)|%(committerdate:unix)|%(upstream:short)|%(upstream:track)' \
    refs/heads/)

set -l paths
set -l heads
set -l branches
set -l wflags
for line in (git -C $root worktree list --porcelain)
    switch (string split -f1 ' ' -- $line)
        case worktree
            set -a paths (string sub -s 10 -- $line)
            set -a heads ""
            set -a branches ""
            set -a wflags ""
        case HEAD
            set heads[-1] (string sub -s 6 -- $line)
        case branch
            set branches[-1] (string replace refs/heads/ '' -- (string sub -s 8 -- $line))
        case locked prunable
            set wflags[-1] (string trim -- "$wflags[-1] "(string split -f1 ' ' -- $line))
    end
end

set -l rows
set -l removable 0
for i in (seq (count $paths))
    set -l path $paths[$i]
    set -l branch $branches[$i]
    set -l sha $heads[$i]
    set -l primary (test $path = $root; and echo yes; or echo no)

    set -l stamp
    set -l track
    set -l upstream
    if test -n "$branch"
        set -l hit (string match -r -- '^'(string escape --style=regex -- $branch)'\|(.*)$' $refinfo)
        if test (count $hit) -ge 2
            set -l fields (string split '|' -- $hit[2])
            set stamp $fields[1]
            set upstream $fields[2]
            set track $fields[3]
        end
    else
        set stamp (git -C $root log -1 --format=%ct $sha 2>/dev/null)
    end

    # Left is what the base has and this does not, right is what only this has. Only the right
    # side is work: a worktree zero commits ahead contains nothing that would be lost.
    set -l counts (string split \t -- (git -C $root rev-list --left-right --count "$base...$sha" 2>/dev/null))
    set -l behind $counts[1]
    set -l ahead $counts[2]
    test -z "$ahead"; and set ahead 0
    test -z "$behind"; and set behind 0

    set -l dirty (git -C $path status --porcelain 2>/dev/null | count)

    # What the remote knows. `gone` means origin deleted the branch, which is what a merged and
    # tidied pull request leaves behind and the one merge signal that survives a squash.
    set -l push
    set -l unpushed 0
    if test -z "$branch"
        set push -
    else if test -z "$upstream"
        set push local
    else if test "$track" = '[gone]'
        set push gone
    else if set -l m (string match -r 'ahead (\d+)' -- $track)
        set unpushed $m[2]
        set push "↑$m[2]"
    else if set -l m (string match -r 'behind (\d+)' -- $track)
        set push "↓$m[2]"
    else
        set push ok
    end

    # Commits that exist in this worktree and nowhere a fetch could bring them back from.
    set -l stranded $unpushed
    if test "$push" = local
        set stranded $ahead
    end

    # Worktrees that belong to another tool are reported but never judged: their lifecycle is
    # that tool's, and a live review session looks identical to an abandoned branch from here.
    set -l owner
    if string match -q '*/.worktrees/review/*' -- $path
        set owner review
    else if string match -q '*/.worktrees/skim' -- $path
        set owner skim
    else if string match -q '*/.claude/worktrees/*' -- $path
        set owner agent
    end

    # A detached HEAD is the one case where removing the worktree destroys commits outright:
    # nothing else points at them, so they are unreachable the moment the worktree is gone.
    set -l orphaned no
    if test -z "$branch"; and test $ahead -gt 0
        if test (git -C $root for-each-ref --contains $sha --count=1 refs/heads refs/remotes | count) -eq 0
            set orphaned yes
        end
    end

    set -l note
    set -l colour normal
    if test $primary = yes
        set note checkout
        set colour brblack
    else if test $orphaned = yes
        set note "detached — $ahead commits exist nowhere else"
        set colour brred
    else if test -n "$owner"
        set note $owner
        set colour brblack
    else if test $dirty -gt 0
        set note 'uncommitted files'
        set colour yellow
    else if test $stranded -gt 0
        set note 'never pushed'
        set colour yellow
    else if test $ahead -eq 0
        set note 'merged — removable'
        set colour green
        set removable (math $removable + 1)
    else if test "$push" = gone
        set note 'branch gone from origin — removable'
        set colour green
        set removable (math $removable + 1)
    else
        set note active
    end

    # Sorted oldest first, because the reason to open this listing is that something has been
    # sitting around. The checkout is pinned above them all rather than ranked among them.
    set -l order $stamp
    test -z "$order"; and set order 9999999999
    test $primary = yes; and set order 0

    set -a rows (printf '%010d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' $order \
        (string replace "$workspace/" '' -- $path) \
        (test -n "$branch"; and echo $branch; or echo (string sub -l 8 -- $sha)) \
        (_wt_age $stamp) "$ahead" "$behind" "$dirty" "$push" \
        (string trim -- "$note $wflags[$i]") $colour)
end

set -l fetched ?
if test -f $common/FETCH_HEAD
    # `date -r` rather than `stat`, whose mtime flag differs between the BSD and GNU builds.
    set fetched (_wt_age (date -r $common/FETCH_HEAD +%s))
end
printf '\n%s%s%s  %s  ·  %d worktree' (set_color --bold) (basename $root) (set_color normal) $base (count $paths)
test (count $paths) -gt 1; and printf s
test $removable -gt 0; and printf ', %d removable' $removable
printf '%s  ·  fetched %s ago%s\n' (set_color brblack) $fetched (set_color normal)

# Padded before colouring: escape sequences count towards printf's field width and would
# knock every column after the first out of line.
set -l width_path 12
set -l width_branch 12
for row in $rows
    set -l f (string split \t -- $row)
    test (string length -- $f[2]) -gt $width_path; and set width_path (string length -- $f[2])
    test (string length -- $f[3]) -gt $width_branch; and set width_branch (string length -- $f[3])
end
test $width_path -gt 44; and set width_path 44
test $width_branch -gt 44; and set width_branch 44

printf '%s  %s  %s  %5s %6s %6s %6s %6s  %s%s\n' (set_color brblack) \
    (string pad -r -w $width_path WORKTREE) (string pad -r -w $width_branch BRANCH) \
    AGE AHEAD BEHIND DIRTY PUSH NOTE (set_color normal)

for row in (printf '%s\n' $rows | sort -n)
    set -l f (string split \t -- $row)
    printf '  %s%s%s  %s%s%s  %5s %6s %6s %6s %6s  %s%s%s\n' \
        (set_color $f[10]) (string pad -r -w $width_path -- (string shorten --left -m $width_path -- $f[2])) (set_color normal) \
        (set_color cyan) (string pad -r -w $width_branch -- (string shorten -m $width_branch -- $f[3])) (set_color normal) \
        $f[4] "+$f[5]" "-$f[6]" $f[7] $f[8] \
        (set_color $f[10]) $f[9] (set_color normal)
end
