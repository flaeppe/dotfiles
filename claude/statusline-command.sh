#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
total_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Absent until the main conversation's first API response, so every field is
# guarded. A hit ratio that stops climbing, or a rising miss count, is the
# visible symptom of something changing the cached prefix mid-session.
cache_hit=$(echo "$input" | jq -r '.prompt_cache.hit_ratio // empty')
cache_warm=$(echo "$input" | jq -r '.prompt_cache.warm // empty')
cache_misses=$(echo "$input" | jq -r '.prompt_cache.misses // 0')

# Tilde-shorten home directory in cwd
cwd_fmt="${cwd/#$HOME/~}"

# Format token count as e.g. 300k or 1.2m
if [[ "$total_tokens" -ge 1000000 ]]; then
  token_fmt=$(awk "BEGIN { printf \"%.1fm\", $total_tokens / 1000000 }")
elif [[ "$total_tokens" -ge 1000 ]]; then
  token_fmt=$(awk "BEGIN { printf \"%.0fk\", $total_tokens / 1000 }")
else
  token_fmt="${total_tokens}"
fi

if [[ -n "$used_pct" ]]; then
  pct_fmt=$(printf "%.0f" "$used_pct")
  usage_fmt="${token_fmt}(${pct_fmt}%)"
else
  usage_fmt="${token_fmt}"
fi

cache_fmt=""
if [[ -n "$cache_hit" ]]; then
  cache_fmt=$(awk "BEGIN { printf \"cache %.0f%%\", $cache_hit * 100 }")
  [[ "$cache_warm" == "false" ]] && cache_fmt="${cache_fmt} cold"
  [[ "$cache_misses" -gt 0 ]] && cache_fmt="${cache_fmt} !${cache_misses}"
fi

segments=("$model")
[[ -n "$cwd_fmt" ]] && segments+=("$cwd_fmt")
segments+=("$usage_fmt")
[[ -n "$cache_fmt" ]] && segments+=("$cache_fmt")

printf "%s" "${segments[0]}"
for s in "${segments[@]:1}"; do printf " | %s" "$s"; done
