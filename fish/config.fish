# Disable fish greeting
set fish_greeting

# -x is --export
# -U is --universal
# -g is --global

# Set better color when printing folders
set -gx LSCOLORS gxfxcxdxbxegedabagacad
alias ls='ls -h --color=auto'

# Starting TMUX on startup, if tmux exists
# If existing session exists -> attach. Otherwise new tmux session
# --------------------------------------------------------
if begin; status --is-interactive; and test -z (echo $TMUX); end
    if not test (tmux attach)
        tmux new-session
    end
end
# -------------------------------------------------------

# Enable ssh-agent env variable at startup
set -x SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"

# Hardware video acceleration (arch only)
set -x LIBVA_DRIVER_NAME vdpau 

# Variables for 'virtualfish' (virtualenvwrapper for fish)
set -x WORKON_HOME $HOME/.virtualenvs
set -x PROJECT_HOME $HOME/repos

set -x PIP_VIRTUALENV_BASE $HOME/.virtualenvs

set -x LC_ALL en_US.UTF-8
set -x LANG en_US.UTF-8
set -x LANGUAGE en_US.UTF-8

set PATH /usr/local/bin/ $PATH

# For convenience updating changelogs in repos
set -x CHANGELOG_GITHUB_TOKEN ""

# Init pyenv
if begin; status --is-interactive; and type -f pyenv > /dev/null; end
    source (pyenv init -|psub)
end

# Start 'virtualfish'
eval (python -m virtualfish compat_aliases)

# GPG key
set -x GPG_TTY (tty)
