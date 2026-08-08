#!/usr/bin/env bash
# Worst-path load size of a skill: SKILL.md + the single largest on-demand leaf
# a run could pull. Leaf files live under references/ or leaves/ (the directory
# name is a human convention, not a runtime hook — progressive disclosure is
# driven by SKILL.md links), so measure both, recursively. Chars are a cheap,
# deterministic token proxy.
# Usage: measure.sh <skill-dir>
set -euo pipefail
d="${1:?usage: measure.sh <skill-dir>}"
[ -f "$d/SKILL.md" ] || { echo "no SKILL.md in $d" >&2; exit 1; }

skill=$(wc -c < "$d/SKILL.md" | tr -d ' ')
leaf=0
while IFS= read -r f; do
  sz=$(wc -c < "$f" | tr -d ' ')
  [ "$sz" -gt "$leaf" ] && leaf=$sz
done < <(find "$d"/references "$d"/leaves -type f -name '*.md' 2>/dev/null)

echo "SKILL.md:         $skill chars"
echo "largest leaf:     $leaf chars"
echo "worst-path load:  $((skill + leaf)) chars"
