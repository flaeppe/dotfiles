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

# Upstream and tracking state for every branch in one call, and the dates the listing sorts
# on. Asking per worktree would fork twice more for a listing already spanning a hundred.
set -l refinfo (git -C $root for-each-ref \
    --format='%(refname:short)|%(committerdate:unix)|%(upstream:short)|%(upstream:track)' \
    refs/heads/)

set -l rows
set -l removable 0
for record in (_wt_trees $root)
    set -l fields (string split \t -- $record)
    set -l path $fields[1]
    set -l sha $fields[2]
    set -l branch $fields[3]
    set -l wflags $fields[4]

    set -l stamp
    set -l upstream
    set -l track
    if test -n "$branch"
        set -l hit (string match -r -- '^'(string escape --style=regex -- $branch)'\|(.*)$' $refinfo)
        if test (count $hit) -ge 2
            set -l parts (string split '|' -- $hit[2])
            set stamp $parts[1]
            set upstream $parts[2]
            set track $parts[3]
        end
    else
        set stamp (git -C $root log -1 --format=%ct $sha 2>/dev/null)
    end

    set -l v (string split \t -- (_wt_verdict $root $path $sha "$branch" $base "$upstream" "$track"))
    set -l state $v[1]
    set -l dirty $v[2]
    set -l ahead $v[3]
    set -l behind $v[4]
    set -l push $v[5]

    set -l owner (_wt_owner $path)
    set -l note
    set -l colour normal
    if test $path = $root
        set note checkout
        set colour brblack
    else if test $state = orphaned
        # Reported above ownership: a tree that is supposed to hold nothing and holds commits
        # is worth saying loudly whoever made it.
        set note "detached — $ahead commits exist nowhere else"
        set colour brred
    else if test -n "$owner"
        set note $owner
        set colour brblack
    else
        switch $state
            case dirty
                set note 'uncommitted files'
                set colour yellow
            case stranded
                set note 'never pushed'
                set colour yellow
            case merged
                set note 'merged — removable'
                set colour green
                set removable (math $removable + 1)
            case gone
                set note 'branch gone from origin — removable'
                set colour green
                set removable (math $removable + 1)
            case '*'
                set note active
        end
    end

    # Sorted oldest first, because the reason to open this listing is that something has been
    # sitting around. The checkout is pinned above them all rather than ranked among them.
    set -l order $stamp
    test -z "$order"; and set order 9999999999
    test $path = $root; and set order 0

    set -a rows (printf '%010d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' $order \
        (string replace "$workspace/" '' -- $path) \
        (test -n "$branch"; and echo $branch; or echo (string sub -l 8 -- $sha)) \
        (_wt_age $stamp) "$ahead" "$behind" "$dirty" "$push" \
        (string trim -- "$note $wflags") $colour)
end

set -l fetched ?
if test -f $common/FETCH_HEAD
    # `date -r` rather than `stat`, whose mtime flag differs between the BSD and GNU builds.
    set fetched (_wt_age (date -r $common/FETCH_HEAD +%s))
end
printf '\n%s%s%s  %s  ·  %d worktree' (set_color --bold) (basename $root) (set_color normal) $base (count $rows)
test (count $rows) -gt 1; and printf s
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
