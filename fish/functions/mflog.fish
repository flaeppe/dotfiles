# TODO: Replace flog with this
function mflog --description 'Fuzzy git log search that outputs hashes for selected commits'
  git log --color=always --decorate --oneline | fzf --ansi --reverse --multi | awk '{ print $1 }' | tr '\n' ' '
end
