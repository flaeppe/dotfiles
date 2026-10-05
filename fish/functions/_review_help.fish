# The help text behind `review --help`, `review help` and `review <subcommand> --help`.
#
#   _review_help             the full usage block
#   _review_help <sub>       the one line for that subcommand (skim, refresh, list, retire, post);
#                            anything else gets the full block
#
# One source of text for every route into it, so the lines cannot drift apart. A new
# subcommand is a new line in `commands` plus its case in `review`.

set -l commands \
    "  review <pr|url> [--stack] [--no-tab]  start or resume a session: head tree for markers, stack tree for code" \
    "  review skim [<pr|url>]                read-only browsing surface across PRs, one reusable worktree" \
    "  review refresh <pr>                   move the head tree onto the PR's new head, markers kept" \
    "  review list                           every session in this repo, live or retired" \
    "  review retire <pr> [--force]          archive findings and suggestions, remove the worktrees" \
    "  review post <pr> [--dry-run]          post .review/post.json as one PR review" \
    "  review help | --help | -h             this text; `review <subcommand> --help` shows one line"

if test -n "$argv[1]"
    set -l sub (string escape --style=regex -- $argv[1])
    set -l line (string match -r -- "^  review $sub( .*)?\$" $commands)
    if test -n "$line"
        string replace -r '^  ' '' -- $line[1]
        return 0
    end
end

echo "Usage: review <pr|url> | review <subcommand> [args]"
echo
printf '%s\n' $commands
echo
echo "<pr> is a number in this repository; <pr|url> also takes a pull-request URL for another one."
echo "--stack also opens the stack tab; --no-tab makes the worktrees and prints the review path."
echo "--force retires despite an open editor or uncommitted stack work; --dry-run posts nothing."
echo
echo "Markers are comments in the code under review, written in the head tree:"
echo "  // REVIEW[n]: text       finding n; REVIEW[n]fix: / ask: / note: = code change / question / private"
echo "  // REVIEW[n]fix+8: text  the finding covers 8 lines; a bare REVIEW[n] is another site for n"
echo "STALE: `refresh` tags a marker STALE(<sha7>:<file>:<line>) when its code line moved; re-place it."
echo "`post` reads .review/post.json (event, body, comments[]), anchors it to the diff, refuses while STALE remains."
echo "Docs: docs/pr-review.md in the dotfiles repository."
