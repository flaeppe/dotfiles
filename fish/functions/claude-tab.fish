# Opens a kitty tab with Claude on the left and the editor on the right, for
# one directory, in the running kitty instance via remote control.
#
#   claude-tab            for the current directory
#   claude-tab <path>

set -l path $argv[1]
if test -z "$path"
    set path $PWD
end
set -l path (realpath $path)
set -l title (basename $path)
set -l claude_cmd "direnv export fish | source; and claude"
set -l editor_cmd 'direnv export fish | source; and nvim -c "OpenTreeAndJump"'

# Its control socket is per-instance (`listen_on` gets `-<pid>` appended), so the
# environment's own value is preferred and a lone listening socket is the fallback.
set -l kitty_socket $KITTY_LISTEN_ON
if test -z "$kitty_socket"
    # `find` rather than a glob, which errors in fish when nothing matches.
    set -l listening (find /tmp -maxdepth 1 -name 'mykitty-*' -type s 2>/dev/null)
    if test (count $listening) -eq 1
        set kitty_socket "unix:$listening[1]"
    end
end

if test -z "$kitty_socket"
    echo "claude-tab: no kitty control socket found -- is remote control on?"
    return 1
end

kitty @ --to $kitty_socket launch --type=tab --tab-title "$title" \
    --cwd $path fish -i -c $claude_cmd >/dev/null
or begin
    echo "claude-tab: could not open a kitty tab (is remote control allowed?)"
    return 1
end
# Belt and suspenders: new tabs already start on the configured default layout
# (tall), but that default is unstated here, so pin it rather than assume it.
kitty @ --to $kitty_socket goto-layout tall >/dev/null 2>&1
kitty @ --to $kitty_socket launch --location=hsplit --cwd $path \
    fish -i -c $editor_cmd >/dev/null 2>&1
