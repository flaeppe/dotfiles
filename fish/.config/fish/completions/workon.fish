complete -x -c workon -a "(find $HOME/*repos/ -type d -mindepth 1 -maxdepth 1 | rev | cut -d '/' -f 1 | rev | uniq)"
