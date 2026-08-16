# The tool that owns a worktree, if any.
#
#   _wt_owner <path>
#
# Empty for a worktree made by hand. The rest have a lifecycle belonging to whatever made
# them, and from the outside a live one is indistinguishable from an abandoned branch, so
# nothing here judges or removes them.

switch $argv[1]
    case '*/.worktrees/review/*'
        echo review
    case '*/.worktrees/skim'
        echo skim
    case '*/.claude/worktrees/*'
        echo agent
end
