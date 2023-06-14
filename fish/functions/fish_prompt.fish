set -l last_status $status
set -l blue (set_color -o blue)
set -l red (set_color -o red)
set -l yellow (set_color -o yellow)

# User
set_color $fish_color_user
echo -n (whoami)
set_color normal

echo -n '@'

# Host
set_color $fish_color_host
echo -n (prompt_hostname)
set_color normal

echo -n ':'

# PWD
set_color $fish_color_cwd
echo -n (prompt_pwd)
set_color normal

__terlar_git_prompt
__fish_hg_prompt

# Line 2
echo
# NIX
if test -n "$IN_NIX_SHELL"
  set_color cyan
  printf '<nix-shell> '
  set_color normal
end
# VIRTUALENV
if set -q VIRTUAL_ENV
    set_color yellow
    printf '(%s) ' (basename (dirname $VIRTUAL_ENV))
    set_color normal
end
# DOCKER HOST
if test $DOCKER_HOST
    set_color blue
    printf '[%s] ' (echo $DOCKER_STACK)
    set_color normal
end

if not test $last_status -eq 0
    set_color $fish_color_error
end

echo -n '➤ '
set_color normal
