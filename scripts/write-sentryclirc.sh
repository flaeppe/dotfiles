#!/bin/bash
# Writes ~/.sentryclirc from pass entry dev/sentry-token.
# Formats the value as [auth]\ntoken=<value>.
#
# - If ~/.password-store doesn't exist: skip silently
# - If ~/.sentryclirc already exists: skip silently
# - If pass entry is missing: print loud warning, continue
set -euo pipefail

TARGET="$HOME/.sentryclirc"

if [[ ! -d "$HOME/.password-store" ]]; then
  exit 0
fi

if [[ -e "$TARGET" ]]; then
  exit 0
fi

token="$(pass show dev/sentry-token 2>/dev/null || true)"

if [[ -z "$token" ]]; then
  echo "" >&2
  echo "  ┌──────────────────────────────────────────────────────────────┐" >&2
  echo "  │  WARNING: pass entry 'dev/sentry-token' not found!          │" >&2
  echo "  │  ~/.sentryclirc was NOT written.                            │" >&2
  echo "  └──────────────────────────────────────────────────────────────┘" >&2
  echo "" >&2
  exit 0
fi

printf '[auth]\ntoken=%s\n' "$token" > "$TARGET"
chmod 600 "$TARGET"
