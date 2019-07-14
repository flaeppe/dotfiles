complete -x -c workon -a "(find $HOME/**repos/ -mindepth 1 -maxdepth 1 -type d | rev | cut -d '/' -f 1 | rev | uniq)"
