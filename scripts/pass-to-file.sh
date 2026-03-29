#!/bin/bash
# Usage: pass-to-file.sh <pass-entry> <target-file> <mode>
#
# Fetches a value from pass and writes it to a file.
#
# - If ~/.password-store doesn't exist: skip silently (pass not set up yet)
# - If target file already exists: skip silently
# - If pass entry is missing: print loud warning, continue
# - Otherwise: write file and chmod
set -euo pipefail

PASS_ENTRY="$1"
TARGET_FILE="$2"
MODE="$3"

if [[ ! -d "$HOME/.password-store" ]]; then
  exit 0
fi

if [[ -e "$TARGET_FILE" ]]; then
  exit 0
fi

value="$(pass show "$PASS_ENTRY" 2>/dev/null || true)"

if [[ -z "$value" ]]; then
  echo "" >&2
  echo "  ┌──────────────────────────────────────────────────────────────┐" >&2
  echo "  │  WARNING: pass entry '$PASS_ENTRY' not found!               │" >&2
  echo "  │  $TARGET_FILE was NOT written.                              │" >&2
  echo "  └──────────────────────────────────────────────────────────────┘" >&2
  echo "" >&2
  exit 0
fi

mkdir -p "$(dirname "$TARGET_FILE")"
printf '%s\n' "$value" > "$TARGET_FILE"
chmod "$MODE" "$TARGET_FILE"
