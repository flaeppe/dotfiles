#!/bin/sh
# Restarts fseventsd when its memory footprint is over the threshold; launchd
# starts a fresh one. Run hourly by the LaunchDaemon, as root.
#
# Usage: fseventsd-restart.sh [--dry-run]
#   --dry-run  print the decision; restart nothing, log nothing.
#
# Test seams: FSEVENTSD_FOOTPRINT_BYTES replaces the reading, FSEVENTSD_KILLALL
# the restart command, FSEVENTSD_RESTART_LOG the log path.
set -eu

# Same line as the me tooling's fseventsd alarm (8 GiB).
THRESHOLD_BYTES=8589934592
LOG="${FSEVENTSD_RESTART_LOG:-/Library/Logs/fseventsd-restart.log}"
KILLALL="${FSEVENTSD_KILLALL:-/usr/bin/killall}"

isDryRun=false
case "${1:-}" in
"") ;;
--dry-run) isDryRun=true ;;
*)
	echo "usage: $0 [--dry-run]" >&2
	exit 2
	;;
esac

# Memory footprint (resident plus compressed) as top's MEM column reports it,
# e.g. "3504K" or "85G".
read_footprint_bytes() {
	pid=$(/usr/bin/pgrep -x fseventsd | /usr/bin/head -n 1) || return 0
	[ -n "$pid" ] || return 0
	/usr/bin/top -l 1 -pid "$pid" -stats mem | /usr/bin/awk '
		NF { size = $1 }
		END {
			sub(/[+-]$/, "", size)
			unit = substr(size, length(size))
			scale = 1
			if (unit == "K") scale = 1024
			if (unit == "M") scale = 1024 ^ 2
			if (unit == "G") scale = 1024 ^ 3
			if (unit == "T") scale = 1024 ^ 4
			printf "%.0f\n", size * scale
		}'
}

footprint_bytes="${FSEVENTSD_FOOTPRINT_BYTES:-$(read_footprint_bytes)}"
if [ -z "$footprint_bytes" ]; then
	echo "fseventsd is not running"
	exit 0
fi

if [ "$footprint_bytes" -le "$THRESHOLD_BYTES" ]; then
	echo "no restart: footprint_bytes=$footprint_bytes threshold_bytes=$THRESHOLD_BYTES"
	exit 0
fi

if [ "$isDryRun" = true ]; then
	echo "would restart: $KILLALL fseventsd (footprint_bytes=$footprint_bytes threshold_bytes=$THRESHOLD_BYTES)"
	exit 0
fi

"$KILLALL" fseventsd
echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) restart footprint_bytes=$footprint_bytes threshold_bytes=$THRESHOLD_BYTES" >>"$LOG"
