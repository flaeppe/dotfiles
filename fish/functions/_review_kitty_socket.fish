# The kitty instance already running, so opening a reviewing surface costs a tab
# rather than a new OS window. The control socket is per-instance (`listen_on`
# gets `-<pid>` appended), so the environment's own value is preferred and a lone
# listening socket is the fallback. Prints nothing if none is found.
#
#   _review_kitty_socket

set -l socket $KITTY_LISTEN_ON
if test -z "$socket"
    # `find` rather than a glob, which errors in fish when nothing matches.
    set -l listening (find /tmp -maxdepth 1 -name 'mykitty-*' -type s 2>/dev/null)
    if test (count $listening) -eq 1
        set socket "unix:$listening[1]"
    end
end
echo $socket
