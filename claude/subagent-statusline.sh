#!/usr/bin/env bash
set -euo pipefail

# One jq process for every task: the line is redrawn constantly and each
# process start is scanned by endpoint agents.
exec jq -c '
  def compact: if . >= 1000 then "\(. / 1000 | round)k" else "\(. | floor)" end;

  .tasks[]
  | (.tokenCount // 0) as $tokenCount
  | (.contextWindowSize // 0) as $contextSize
  | ($tokenCount | compact) as $tokens
  | (if $contextSize > 0 then "\($tokenCount / $contextSize * 100 | round)% (\($tokens))" else $tokens end) as $usage
  | {
      id,
      content: "\(.name // .label // "agent") · \(.model // "resolving…") · \(.effort // "-") · \($usage)"
    }'
