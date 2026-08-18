#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

echo "$input" | jq -c '.tasks[]' | while IFS= read -r task; do
  id=$(echo "$task" | jq -r '.id')
  name=$(echo "$task" | jq -r '.name // .label // "agent"')
  model=$(echo "$task" | jq -r '.model // "resolving…"')
  effort=$(echo "$task" | jq -r '.effort // "-"')
  token_count=$(echo "$task" | jq -r '.tokenCount // 0')
  ctx_size=$(echo "$task" | jq -r '.contextWindowSize // 0')

  if [[ "$ctx_size" -gt 0 ]]; then
    usage=$(awk "BEGIN { printf \"%.0f%%\", ($token_count / $ctx_size) * 100 }")
  else
    usage="${token_count}"
  fi

  content="${name} · ${model} · ${effort} · ${usage}"
  jq -cn --arg id "$id" --arg content "$content" '{id: $id, content: $content}'
done
