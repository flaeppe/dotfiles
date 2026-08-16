# Completions for `wt`.
#
# `rm` offers only the worktrees it would actually consider: the repository's own checkout
# and the trees `review` owns are absent, because `wt rm` refuses both and completing to a
# name that can only produce an error is worse than completing to nothing.

complete -c wt -f

complete -c wt -n __fish_use_subcommand -a new -d 'Create a worktree and prepare it'
complete -c wt -n __fish_use_subcommand -a rm -d 'Remove worktrees that hold nothing'
complete -c wt -n __fish_use_subcommand -s a -l all -d 'Every repository under the workspace root'
complete -c wt -n __fish_use_subcommand -s h -l help -d 'Usage'

complete -c wt -n '__fish_seen_subcommand_from rm' -a '(_wt_candidates)'
complete -c wt -n '__fish_seen_subcommand_from rm' -s f -l force -d 'Remove even when work would be lost'

# The branch argument only, never the name: a new worktree's name is not something that
# exists yet to be completed.
complete -c wt -n '__fish_seen_subcommand_from new; and __fish_is_nth_token 3' \
    -a '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null; git for-each-ref --format="%(refname:lstrip=3)" refs/remotes/origin 2>/dev/null)'
