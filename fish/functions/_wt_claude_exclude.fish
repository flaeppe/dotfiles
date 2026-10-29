# Stop a linked worktree from loading the main checkout's instructions on top of its own.
#
#   _wt_claude_exclude <worktree> <main-checkout>
#
# Claude Code started in `<main>/.worktrees/x` walks up through `<main>` as well, so
# `<main>/CLAUDE.md` and `<main>/.claude/rules/**` load alongside the worktree's own copies.
# The excludes go in the worktree's `settings.local.json`, which is per-worktree, so the main
# checkout is unaffected. Other keys already in that file are kept.

set -l tree $argv[1]
set -l main $argv[2]
set -l settings "$tree/.claude/settings.local.json"

mkdir -p "$tree/.claude"
set -l existing "{}"
if test -s $settings
    set existing (cat $settings)
end
set -l merged (printf '%s' $existing | jq \
    --arg claude_md "$main/CLAUDE.md" --arg rules "$main/.claude/rules/**" \
    '.claudeMdExcludes = ((.claudeMdExcludes // []) + [$claude_md, $rules] | unique)')
or begin
    echo "_wt_claude_exclude: $settings is not valid JSON, left alone"
    return 1
end
printf '%s\n' $merged >$settings

# Untracked and machine-specific: kept out of `git status`. Git resolves `info/exclude` to the
# repository-wide file, so every worktree and the main checkout ignore the settings file.
set -l exclude (git -C $tree rev-parse --path-format=absolute --git-path info/exclude)
mkdir -p (dirname $exclude)
if not grep -qxF ".claude/settings.local.json" $exclude 2>/dev/null
    echo ".claude/settings.local.json" >>$exclude
end
