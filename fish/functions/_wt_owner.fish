# The tool that owns a worktree, if any.
#
#   _wt_owner <path>
#
# Empty for a worktree made by hand. Naming the owner is all this does; what follows from it
# differs per tool. A review session is the only one holding state another command is keeping
# for it, and so the only one that must not be removed from here.

switch $argv[1]
    case '*/.worktrees/review/*'
        echo review
    case '*/.worktrees/skim'
        echo skim
    case '*/.claude/worktrees/*'
        echo agent
end
