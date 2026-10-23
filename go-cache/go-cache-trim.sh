#!/bin/sh
# Deletes Go build cache entries not used within GO_CACHE_MAX_AGE_MIN minutes.
# Go refreshes an entry's mtime on use, so mtime age is least-recently-used
# order. Go's own trim only runs at 5 days and the cache has no size cap.
#
# Env: GO_CACHE_DIR (default ~/Library/Caches/go-build, basename must be
# go-build), GO_CACHE_MAX_AGE_MIN (default 1440).
# Stdout: one line, "go-cache-trim: removed N files, M MB freed, now X MB".
# Exit: non-zero, nothing deleted, when the directory is missing or misnamed.
set -eu

cache_dir=${GO_CACHE_DIR:-$HOME/Library/Caches/go-build}
max_age_minutes=${GO_CACHE_MAX_AGE_MIN:-1440}

if [ ! -d "$cache_dir" ]; then
  echo "go-cache-trim: not a directory: $cache_dir" >&2
  exit 1
fi
if [ "$(basename "$cache_dir")" != "go-build" ]; then
  echo "go-cache-trim: refusing, directory is not named go-build: $cache_dir" >&2
  exit 1
fi
case "$max_age_minutes" in
  '' | *[!0-9]*)
    echo "go-cache-trim: GO_CACHE_MAX_AGE_MIN must be a number: $max_age_minutes" >&2
    exit 1
    ;;
esac

size_kb() {
  du -sk "$cache_dir" | cut -f1
}

size_before_kb=$(size_kb)

# trim.txt and README are Go's own bookkeeping files.
removed=$(find "$cache_dir" -type f -mmin "+$max_age_minutes" \
  ! -name trim.txt ! -name README -print -delete | wc -l | tr -d ' ')

size_after_kb=$(size_kb)
freed_kb=$((size_before_kb - size_after_kb))
if [ "$freed_kb" -lt 0 ]; then
  freed_kb=0 # concurrent Go builds grew the cache during the run
fi

echo "go-cache-trim: removed $removed files, $((freed_kb / 1024)) MB freed, now $((size_after_kb / 1024)) MB"
