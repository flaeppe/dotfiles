#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
total_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

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

if [[ -n "$cwd_fmt" ]]; then
  printf "%s | %s | %s" "$model" "$cwd_fmt" "$usage_fmt"
else
  printf "%s | %s" "$model" "$usage_fmt"
fi
