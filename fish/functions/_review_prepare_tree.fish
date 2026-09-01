# Make a fresh worktree usable rather than merely checked out: an editor that resolves
# what it is looking at, and a checkout that accepts a commit.
#
#   _review_prepare_tree <main-root> <tree> <role> [<pr>]
#
# Reached from `review <pr>` and `review skim`, which both need it and must agree: a
# surface prepared one way and another prepared differently is a language server that
# works in one tab and not the next.
#
# Every step is guarded on what is already there, so this is safe to re-run against a
# worktree being reused.

set -l root $argv[1]
set -l tree $argv[2]
set -l role $argv[3]
set -l pr $argv[4]

set -l label "skim"
if test -n "$pr"
    set label "review $pr"
end

# Per-checkout tool configuration that is gitignored, and therefore absent from a fresh
# worktree. Extend this list with whatever a project keeps untracked; `.envrc` is the
# load-bearing one, since without it direnv never activates and the worktree has no
# toolchain at all, so no language server can start.
set -l LOCAL_CONFIG .envrc .ignore .sqruff .cbmignore postgres-language-server.jsonc .ctags.d

# Dependency trees, symlinked rather than installed: a fresh worktree has none,
# and without them a language server reports every import as unresolved and any
# typecheck fails. Symlinked because installing is project-specific and slow,
# and reviewing rarely needs dependencies that differ from the main checkout's.
# Stale if the PR itself changes dependencies -- install into the worktree by hand
# in that case.
#
# A pnpm/npm/yarn workspace keeps one node_modules per package, not only at the root,
# so each name here is walked rather than looked up once at $root -- pruned at every
# match, both because a package's own transitive deps must never be linked
# individually (only the workspace-package-level tree they hang off) and because
# descending into them is most of a monorepo's file count for nothing this needs.
# `.git` and `.worktrees` are pruned too: the former never holds a workspace package,
# and the latter holds every other worktree of this same repository, which would
# otherwise be walked once per worktree that happens to exist.
#
# Only safe for trees that hold no path back to where they were installed. One that
# does -- and one that carries the language server itself -- needs `.review/setup`
# below, which can rewrite it per worktree.
#
# Known ceiling: a workspace package's node_modules routinely holds a symlink to a
# sibling package's own source, by a path relative to that package -- correct when the
# tree was installed in place, but a *symlinked* node_modules resolves such a link
# through the real directory it points at, landing back in $root regardless of which
# worktree asked. First-party code under review can therefore resolve to the main
# checkout's copy instead of this worktree's, which reads as correct and is not --
# exactly the trap `.review/setup` exists to fix for a Python virtualenv's absolute
# import path, just reached by a relative one here. A repository where packages
# actually import each other this way needs the same kind of hook, run after this
# function, to repoint those particular links.
set -l LINK_DIRS node_modules

for name in $LOCAL_CONFIG
    if test -e "$root/$name"; and not test -e "$tree/$name"
        cp -R "$root/$name" "$tree/$name"
    end
end

# A symlink is not a directory, so a `.gitignore` written `node_modules/` (trailing
# slash, directory-only) does not match the links this loop creates, and `git add -A`
# would commit one as a mode 120000 blob holding this machine's absolute path -- CI's
# install then fails with ENOENT descending into a path that only ever existed here.
#
# Fixed by adding an unslashed line -- `node_modules`, no trailing `/` -- to
# `$GIT_COMMON_DIR/info/exclude`, which every worktree of this repository and the main
# checkout already read. Unslashed matches a symlink as well as a directory, at any
# depth, so it also covers every nested link the walk below creates, and it fixes any
# repository whose own `.gitignore` got the slash wrong without this function needing
# to know or care where the repository's ignore file lives.
#
# Shared, and deliberately not `core.excludesFile`: that setting names a single file
# and so replaces the whole effective excludes file rather than adding to it. Where it
# is unset -- the common case -- git still honours a default XDG path
# (`$XDG_CONFIG_HOME/git/ignore`, typically `~/.config/git/ignore`) that no `git
# config` query reports, only git itself. Pointing it at a per-worktree file therefore
# stops that default applying inside the worktree, un-ignoring `.envrc`, every other
# `LOCAL_CONFIG` entry above and `.review/` below -- committing secrets through the
# same `git add -A` this guards against. `$GIT_COMMON_DIR/info/exclude` only ever adds
# patterns, so it carries no such risk.
set -l common_exclude (git -C $tree rev-parse --path-format=absolute --git-common-dir)/info/exclude
for name in $LINK_DIRS
    if not grep -qxF "$name" $common_exclude 2>/dev/null
        echo "$name" >>$common_exclude
    end
end

for name in $LINK_DIRS
    for found in (find "$root" -name .git -prune -o -name .worktrees -prune -o -type d -name "$name" -print -prune)
        set -l rel (string replace -- "$root/" "" $found)
        set -l parent (dirname "$tree/$rel")
        if not test -d $parent
            # The workspace package's own source isn't in this worktree -- untracked
            # or gitignored there -- so there is nowhere to hang the link. Named
            # rather than left to a bare `ln: No such file or directory`.
            echo "$label: WARNING $rel has no parent directory in the $role worktree, skipping that link"
            continue
        end
        if not test -e "$tree/$rel"
            ln -s "$found" "$tree/$rel"
        end
        # Verified rather than assumed: a link this function believes it excluded but
        # git does not is a defect to report at creation time, not one to discover from
        # a broken CI run days later.
        if not git -C $tree check-ignore -q -- $rel
            echo "$label: WARNING $rel is a symlink git does not ignore -- committing it will break CI"
        end
    end
end
mkdir -p "$tree/.review"

# Per-repo worktree preparation, for what copying and symlinking cannot express.
#
# A language server is often installed into the project's dependency tree rather than
# onto PATH, so a worktree without that tree has no type checking, no definitions and no
# references at all -- not merely unresolved imports. Materialising one is
# ecosystem-specific, and it usually has to be rewritten afterwards: dependency trees
# routinely pin the first-party import root to an absolute path, and one that still
# points at the main checkout resolves the code under review to whatever the default
# branch happens to hold.
#
# That is knowledge the repository has and this function cannot, so the repository
# supplies it. `.review/` is already ignored, so the hook needs no ignore entry.
#
# Retried until it succeeds: the sentinel is written only on exit 0, so a hook that
# failed halfway runs again on the next invocation instead of leaving a worktree that is
# silently half-prepared.
#
# REVIEW_PR is empty for the skim surface, which is not pinned to a PR -- a hook that
# needs it must tolerate that rather than assume a number.
if test -x "$root/.review/setup"; and not test -e "$tree/.review/setup-done"
    echo "$label: preparing the $role worktree"
    pushd $tree
    REVIEW_MAIN=$root REVIEW_PR=$pr REVIEW_ROLE=$role "$root/.review/setup"
    set -l prepared $status
    popd
    if test $prepared -eq 0
        touch "$tree/.review/setup-done"
    else
        echo "$label: WARNING .review/setup failed for the $role worktree"
        echo "             language servers will be missing until it succeeds"
    end
end

# The one part of an install that linking a dependency tree cannot stand in for. `prepare` is
# where a package manager installs git hooks, and hooks are written into the worktree rather
# than into the tree that was linked, so a fresh worktree has none: the pre-commit hook is
# named but missing, and git refuses the commit. A worktree that cannot be committed from is
# not usable, whatever else was prepared for it.
#
# Keyed on a dependency tree that was never installed here, which is exactly what the links
# above leave behind. A repository whose dependencies are absent has no hooks installed
# anywhere and needs nothing done about it.
#
# `npm` rather than whichever package manager the repository uses: yarn and pnpm arrive with
# the project toolchain, which is not active in this shell, while npm sits next to node on
# PATH -- and running a script with the local `.bin` ahead of it is the one thing every
# package manager does identically. `--if-present` is what makes this a no-op wherever there
# is nothing to prepare.
#
# Known ceiling: `prepare` is also the pre-publish build hook, so a repository that compiles
# there pays that build once per worktree; narrow this to the repositories that install hooks
# if one ever turns up.
#
# Retried like the hook above, and for the same reason: the sentinel is written only on exit 0.
if test -e "$tree/package.json"; and test -e "$tree/node_modules"; and not test -e "$tree/.review/prepare-done"
    pushd $tree
    npm run --if-present --silent prepare
    set -l prepared $status
    popd
    if test $prepared -eq 0
        touch "$tree/.review/prepare-done"
    else
        echo "$label: WARNING prepare failed for the $role worktree"
        echo "             git hooks are missing, so commits needing one will be refused"
    end
end

# After the hook, which may well have written the `.envrc` that direnv is being asked
# to trust.
if test -e "$tree/.envrc"
    direnv allow $tree 2>/dev/null
end
