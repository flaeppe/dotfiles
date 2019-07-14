#!/usr/bin/env bash

set -e

usage() {
  echo "Usage: $0 [OPTIONS] COMMAND"
  echo ""
  echo "Options"
  echo "  -h Display this message and quit."
  echo ""
  echo "Commands:"
  echo "  install [module]"
  exit
}

fail() {
  echo "ERROR: $1"
  exit 1
}

dot__install() {
  [ -z $1 ] && echo "Usage: install [module]" && exit
  [ ! -d "./${1}" ] && fail "Module \"${1}\" not found"
  if [ -f "./${1}/.init.sh" ]; then
    "./${1}/.init.sh" || fail "Executing init file failed"
  fi
  stow --ignore '\.init\.sh' --ignore '\.post_install\.sh' $1
  echo "Module \"${1}\" has been successfully installed."
  if [ -f "./${1}/.post_install.sh" ]; then
    "./${1}/.post_install.sh" || fail "Executing post install file failed"
  fi
}

dot() {
  if type "dot__$1" > /dev/null 2>&1; then
    "dot__$1" "${@:2}"
  else
    echo "ERROR: Command \"$1\" not found."
    echo ""
    usage
  fi
}

while getopts "hvf:" optchar
do
  case "${optchar}" in 
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[ -z $1 ] && usage
dot $@
