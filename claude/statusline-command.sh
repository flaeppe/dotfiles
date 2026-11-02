#!/usr/bin/env bash
set -euo pipefail

# The status line is redrawn constantly and every process start is scanned by
# endpoint agents, so the whole line is built by a single jq process.
#
# Absent until the main conversation's first API response, so every
# prompt_cache field is guarded. A hit ratio that stops climbing, or a rising
# miss count, is the visible symptom of something changing the cached prefix
# mid-session.
exec jq -j '
  # 999, 123k, 1.2m
  def compact:
    floor
    | if . >= 1000000 then (. / 100000 | round) as $tenths | "\($tenths / 10 | floor).\($tenths % 10)m"
      elif . >= 1000 then "\(. / 1000 | round)k"
      else tostring end;

  (.context_window.total_input_tokens // 0 | compact) as $tokens
  | .context_window.used_percentage as $usedPercentage
  | .prompt_cache.hit_ratio as $hitRatio
  | (.prompt_cache.warm == false) as $isCold
  | (.prompt_cache.misses // 0) as $misses
  | [
      (.model.display_name // "unknown"),
      ((.workspace.current_dir // "") as $cwd
        | if $cwd == "" then empty
          elif $cwd | startswith($ENV.HOME) then "~" + $cwd[($ENV.HOME | length):]
          else $cwd end),
      (if $usedPercentage == null then $tokens else "\($tokens)(\($usedPercentage | round)%)" end),
      (if $hitRatio == null then empty
        else "cache \($hitRatio * 100 | round)%"
          + (if $isCold then " cold" else "" end)
          + (if $misses > 0 then " !\($misses)" else "" end) end)
    ]
  | join(" | ")'
