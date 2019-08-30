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


run_init() {
  OS=$(echo "`uname`" | tr '[:upper:]' '[:lower:]')
  if [ -f "./${1}/.init.sh" ]; then
    echo "Running non platform specific init script"
    "./${1}/.init.sh" || fail "Executing non platform specific init script failed"
  fi

  if [ -f "./${1}/.init_${OS}.sh" ]; then
    echo "Running init script for: \"${OS}\""
    "./${1}/.init_${OS}.sh" || fail "Executing init script for \"${OS}\" failed"
  fi
}


run_post_install() {
  OS=$(echo "`uname`" | tr '[:upper:]' '[:lower:]')
  if [ -f "./${1}/.post_install.sh" ]; then
    echo "Running non platform specific post install script"
    "./${1}/.post_install.sh" || fail "Executing non platform specific post install script failed"
  fi

  if [ -f "./${1}/.post_install_${OS}.sh" ]; then
    echo "Running post install script for: \"${OS}\""
    "./${1}/.post_install_${OS}.sh" || fail "Executing post install script for \"${OS}\" failed"
  fi
}


dot__install() {
  echo "`uname` detected"
  [ -z $1 ] && echo "Usage: install [module]" && exit
  [ ! -d "./${1}" ] && fail "Module \"${1}\" not found"
  run_init $1
  stow $1
  echo "Module \"${1}\" has been successfully installed."
  run_post_install $1
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
