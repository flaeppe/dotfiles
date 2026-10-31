#!/bin/sh
# Bounds the Go build cache in two passes. Go refreshes an entry's mtime on
# use, so mtime order is least-recently-used order. Go's own trim only runs at
# 5 days and the cache has no size cap.
#   1. age:  delete entries unused for GO_CACHE_MAX_AGE_MIN minutes.
#   2. size: if the cache is still over GO_CACHE_MAX_SIZE_MB, delete the
#            oldest-mtime entries until it is under.
#
# Env: GO_CACHE_DIR (default ~/Library/Caches/go-build, basename must be
# go-build), GO_CACHE_MAX_AGE_MIN (default 1440), GO_CACHE_MAX_SIZE_MB
# (default 10240).
# Stdout: one line, "go-cache-trim: age pass removed N files (M MB), size pass
# removed N files (M MB), now X MB".
# Exit: non-zero, nothing deleted, when the directory is missing or misnamed
# or an env var is not a number.
set -eu

cache_dir=${GO_CACHE_DIR:-$HOME/Library/Caches/go-build}
max_age_minutes=${GO_CACHE_MAX_AGE_MIN:-1440}
max_size_mb=${GO_CACHE_MAX_SIZE_MB:-10240}

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
case "$max_size_mb" in
  '' | *[!0-9]*)
    echo "go-cache-trim: GO_CACHE_MAX_SIZE_MB must be a number: $max_size_mb" >&2
    exit 1
    ;;
esac

size_kb() {
  du -sk "$cache_dir" | cut -f1
}

# Prints "N MB" for the kilobytes a pass freed; concurrent Go builds can grow
# the cache during a pass, so a negative difference counts as zero.
freed_mb() {
  freed_kb=$(($1 - $2))
  if [ "$freed_kb" -lt 0 ]; then
    freed_kb=0
  fi
  echo $((freed_kb / 1024))
}

# Deletes oldest-mtime files until $1 KB have been freed; prints the file
# count. stat %b is allocated 512-byte blocks, the unit du sums, so freed
# space is counted the way the cap is measured. trim.txt and README are Go's
# own bookkeeping files.
delete_oldest_kb() {
  find "$cache_dir" -type f ! -name trim.txt ! -name README \
    -exec stat -f '%m %b %N' {} + | sort -n | {
    need_kb=$1
    count=0
    freed_kb=0
    while [ "$freed_kb" -lt "$need_kb" ] && read -r _ blocks path; do
      rm -f "$path"
      count=$((count + 1))
      freed_kb=$((freed_kb + blocks / 2))
    done
    echo "$count"
  }
}

size_start_kb=$(size_kb)

age_removed=$(find "$cache_dir" -type f -mmin "+$max_age_minutes" \
  ! -name trim.txt ! -name README -print -delete | wc -l | tr -d ' ')
size_after_age_kb=$(size_kb)

size_removed=0
max_size_kb=$((max_size_mb * 1024))
if [ "$size_after_age_kb" -gt "$max_size_kb" ]; then
  size_removed=$(delete_oldest_kb $((size_after_age_kb - max_size_kb)))
fi
size_end_kb=$(size_kb)

echo "go-cache-trim: age pass removed $age_removed files ($(freed_mb "$size_start_kb" "$size_after_age_kb") MB)," \
  "size pass removed $size_removed files ($(freed_mb "$size_after_age_kb" "$size_end_kb") MB)," \
  "now $((size_end_kb / 1024)) MB"
