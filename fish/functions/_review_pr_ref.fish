# The PR argument `review` and `review skim` accept: a bare number, meaning a PR in
# the current repository, or a full GitHub pull-request URL, meaning one in whatever
# repository the URL names -- pasted straight out of a browser tab or a Slack link,
# own PRs included.
#
#   _review_pr_ref <ref>
#
# A bare number is echoed back unchanged. A URL is resolved to the sibling clone its
# repository lives in -- the same flat-workspace layout `wt` and the org-wide PR list
# already assume -- and echoes "<clone>\t<number>" instead, so the caller can re-run
# itself there rather than operating git commands against the wrong repository.

set -l ref $argv[1]
if string match -qr '^\d+$' -- $ref
    printf '%s\n' $ref
    return 0
end

set -l parts (string match -r 'github\.com/[^/]+/([^/]+)/pull/(\d+)' -- $ref)
if test -z "$parts"
    echo "review: '$ref' is not a PR number or a pull-request URL" >&2
    return 1
end
set -l repo $parts[2]
set -l number $parts[3]

set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if test -z "$common"
    echo "review: not inside a git repository" >&2
    return 1
end
set -l workspace (dirname (dirname $common))
set -l clone "$workspace/$repo"
if not test -d $clone
    echo "review: no local clone of $repo at $clone" >&2
    return 1
end
printf '%s\t%s\n' $clone $number
