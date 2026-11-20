#!/bin/sh
# Installs the fseventsd-restart LaunchDaemon. Run as root: sudo ./install.sh
#
# The script is copied to a root-owned path: a root daemon must not execute a
# file the user can rewrite.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

source_dir=$(cd "$(dirname "$0")" && pwd)
label=com.petter.fseventsd-restart
plist=/Library/LaunchDaemons/$label.plist

install -d -m 755 -o root -g wheel /usr/local/libexec
install -m 755 -o root -g wheel "$source_dir/fseventsd-restart.sh" /usr/local/libexec/fseventsd-restart.sh
install -m 644 -o root -g wheel "$source_dir/$label.plist" "$plist"

launchctl bootout "system/$label" 2>/dev/null || true # absent on first install
launchctl bootstrap system "$plist"
launchctl print "system/$label" | head -n 5
