# Fuzzy-jump between kitty tabs by checkout, running process and MRU order.
# No match -> the typed text is a project name, resolved via `sam scopes
# --paths`, and a new tab opens there.
#
#   tab-picker

set -l socket (_review_kitty_socket)
if test -z "$socket"
    echo "tab-picker: no kitty control socket found -- is remote control on?"
    read -P "press enter to close "
    return 1
end

# The working directory comes out raw: turning one into a checkout name means
# walking up to a `.git`, which git does and jq cannot. `claude_state` is read
# across every window rather than only the active pane, so the marker survives
# an overlay or a split it was not set on -- the same rule the tab bar applies.
set -l jq_filter '
  [.[].tabs[]]
  | map(
      (.windows | min_by(.created_at)) as $oldest
      | (first(.windows[] | select(.is_active)) // .windows[0]) as $active
      | {
          id: .id,
          mru: ($active.last_focused_at // 0),
          cwd: ($oldest.cwd // ""),
          running: (.title // ""),
          state: ([.windows[].user_vars.claude_state | select(. != null and . != "")] | first // "")
        }
    )
  | sort_by(-.mru)
  | .[]
  | [(.id | tostring), .cwd, .running, .state] | @tsv
'
set -l raw (kitty @ --to $socket ls | jq -r $jq_filter)

# One git call per distinct directory, memoised across tabs that share one --
# several tabs in the same checkout is the normal case, not the exception.
set -l seen_dirs
set -l seen_labels
set -l rows
for row in $raw
    set -l f (string split \t -- $row)
    set -l label
    set -l idx (contains -i -- "$f[2]" $seen_dirs)
    if test -n "$idx"
        set label $seen_labels[$idx]
    else
        set label (_tab_checkout "$f[2]")
        set -a seen_dirs "$f[2]"
        set -a seen_labels "$label"
    end
    # Quoted: a directory in no repository yields an empty label, and an
    # unquoted empty variable would drop the column rather than blank it.
    set -a rows (string join \t -- "$f[1]" "$label" "$f[3]" "$f[4]")
end

set -l picked (printf '%s\n' $rows | fzf --delimiter \t --with-nth=2.. --print-query --prompt 'tab> ')
switch $status
    case 130
        return 0
    case 0
        set -l fields (string split \t -- $picked[2])
        kitty @ --to $socket focus-tab --match id:$fields[1]
        return 0
end

# No match: fall through to opening the query as a project.
set -l query $picked[1]
if test -z "$query"
    return 0
end

set -l sam_home $ME_HOME
if test -z "$sam_home"
    set sam_home "$HOME/anyfin/.me"
end
set -l sam_bin "$sam_home/bin/sam"
if not test -x $sam_bin
    echo "tab-picker: sam is not installed, cannot resolve '$query' as a project"
    read -P "press enter to close "
    return 1
end

set -l matches (cd $sam_home && $sam_bin scopes --paths | string match -i "*$query*")
set -l match $matches[1]
if test -z "$match"
    echo "tab-picker: no tab or project matches '$query'"
    read -P "press enter to close "
    return 1
end

kitty @ --to $socket launch --type=tab --cwd $match --tab-title (basename $match)
