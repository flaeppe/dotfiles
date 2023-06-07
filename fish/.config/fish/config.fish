# Disable fish greeting
set fish_greeting

# -x is --export
# -U is --universal
# -g is --global

# Set better color when printing folders
# BSD
set -gx LSCOLORS gxfxcxdxbxegedabagacad
# Linux
set -gx LS_COLORS 'di=36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'
set -gx CLICOLOR 1

# TODO: Remove once fish is maintained by Home Manager(?)
set -x EDITOR nvim

# Set date format language for ls
set -x LANG en_US.UTF-8
# TODO: Figure out how this coloring is better controlled by /usr/share/fish/functions/ls.fish
if [ (uname) = "Darwin" ]
    alias ls='ls -h'
else
    alias ls='ls -h --color=auto'
end

# Starting TMUX on startup, if tmux exists
# If existing session exists -> attach. Otherwise new tmux session
# --------------------------------------------------------
if begin; type -q tmux; and status --is-interactive; and test -z (echo $TMUX); end
    tmux attach
    if test $status -gt 0
        tmux new-session
    end
end
# -------------------------------------------------------

# Enable ssh-agent env variable at startup
if [ (uname) = "Linux" ]
    set -x SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"
end

# Hardware video acceleration
if [ (uname) = "Linux" ]
    set -x LIBVA_DRIVER_NAME vdpau
end

# Disable 'activate.fish' auto setting and displaying fish status
set -x VIRTUAL_ENV_DISABLE_PROMPT 1

set -x LC_ALL en_US.UTF-8
set -x LANGUAGE en_US.UTF-8

set PATH /usr/local/bin/ $PATH

# Init pyenv
if begin; type -q pyenv; and status --is-interactive; end
    source (pyenv init -|psub)
end

# GPG key
set -x GPG_TTY (tty)

# FZF stuff
set -x FZF_DEFAULT_COMMAND "rg --files --hidden --glob '!.git/*'"

# Set pyenv root path to default value to avoid anything
# unexpected if that default would change
set -x PYENV_ROOT "$HOME/.pyenv"

# Set SSL backend for curl and compile flags for when compiling it
if [ (uname) = "Darwin" ]
    set -x PYCURL_SSL_LIBRARY openssl
    set -x LDFLAGS -L/usr/local/opt/openssl/lib
    set -x CPPFLAGS -I/usr/local/opt/openssl/include
end

# Enable fzf integration for enhanced autocompletion of cheat
set -x CHEAT_USE_FZF true
