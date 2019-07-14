complete -x -c workon -a "(find $HOME -mindepth 1 -maxdepth 3 -path '$HOME*repos/*' -prune -type d 2>/dev/null | rev | cut -d '/' -f 1 | rev | uniq)"
