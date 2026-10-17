# Toggle Claude Code's Artifact tool. Its schema costs ~12k tokens at every session and
# subagent start, so it stays denied unless a page is wanted. Takes effect for sessions
# started afterwards.
#
#   claude-artifact on       remove "Artifact" from permissions.deny
#   claude-artifact off      add it back
#   claude-artifact          print the current state
function claude-artifact --description "Toggle the Claude Code Artifact tool"
    set -l settings ~/.claude/settings.json
    switch "$argv[1]"
        case on
            jq '.permissions.deny -= ["Artifact"]' $settings >$settings.tmp; and mv $settings.tmp $settings
        case off
            jq '.permissions.deny = ((.permissions.deny // []) - ["Artifact"] + ["Artifact"])' $settings >$settings.tmp; and mv $settings.tmp $settings
        case ''
        case '*'
            echo "usage: claude-artifact [on|off]" >&2
            return 2
    end
    if jq -e '(.permissions.deny // []) | index("Artifact")' $settings >/dev/null
        echo "Artifact: off (denied)"
    else
        echo "Artifact: on"
    end
end
