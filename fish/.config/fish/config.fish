# Disable fish greeting
set fish_greeting

# -x is --export
# -U is --universal
# -g is --global

# Set better color when printing folders
set -gx LSCOLORS gxfxcxdxbxegedabagacad
set -gx CLICOLOR 1

# Set date format language for ls
set -x LANG en_US.UTF-8
alias ls='ls -h'

# Starting TMUX on startup, if tmux exists
# If existing session exists -> attach. Otherwise new tmux session
# --------------------------------------------------------
if begin; test (type -q tmux); and status --is-interactive; and test -z (echo $TMUX); end
    if not test (tmux attach)
        tmux new-session
    end
end
# -------------------------------------------------------

# Enable ssh-agent env variable at startup
set -x SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"

# Hardware video acceleration (arch only)
set -x LIBVA_DRIVER_NAME vdpau 

# Disable 'activate.fish' auto setting and displaying fish status
set -x VIRTUAL_ENV_DISABLE_PROMPT 1

set -x LC_ALL en_US.UTF-8
set -x LANGUAGE en_US.UTF-8

set PATH /usr/local/bin/ $PATH

# Init pyenv
if begin; test (type -q pyenv); and status --is-interactive; end
    source (pyenv init -|psub)
end

# GPG key
set -x GPG_TTY (tty)
