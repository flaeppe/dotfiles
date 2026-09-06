# Fuzzy-jump between kitty tabs by project, running process and MRU order.
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

set -l jq_filter '
  def project_of(cwd):
    (cwd // "") | rtrimstr("/") | split("/") as $parts
    | ($parts | index("anyfin")) as $ai
    | if $ai != null and ($ai + 1) < ($parts | length) then $parts[$ai + 1]
      elif ($parts | index(".dotfiles")) != null then ".dotfiles"
      else ($parts[-1] // "")
      end;

  [.[].tabs[]]
  | map(
      (.windows | min_by(.created_at)) as $oldest
      | (first(.windows[] | select(.is_active)) // .windows[0]) as $active
      | {
          id: .id,
          mru: ($active.last_focused_at // 0),
          project: (project_of($oldest.cwd) | ltrimstr(".") | .[0:12]),
          running: (.title // ""),
          state: ($active.user_vars.state // "")
        }
    )
  | sort_by(-.mru)
  | .[]
  | [(.id | tostring), .project, .running, .state] | @tsv
'
set -l rows (kitty @ --to $socket ls | jq -r $jq_filter)

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
