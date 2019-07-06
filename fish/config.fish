# -x is --export
# -U is --universal
# -g is --global

# Set better color when printing folders
set -gx LSCOLORS gxfxcxdxbxegedabagacad
alias ls='ls -h --color=auto'

# Enable ssh-agent env variable at startup
set -x SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"

# Configure alias for dotfiles repository
alias dotfiles='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'

# Hardware video acceleration
set -x LIBVA_DRIVER_NAME vdpau 

# Fish color
set fish_color_normal white
set fish_color_error red
set fish_color_user brgreen
set fish_color_host normal
set fish_color_cwd green
set fish_color_cwd_root red
set fish_color_command --bold
