#!/usr/bin/env bash
# Daily Codex quota-window alignment poke, meant for the launchd timer.
#
# Codex's ~5h primary rate-limit window starts on the account's first
# completed turn after the previous window expired (Petter, 2026-09-10) --
# reading the quota endpoint does not count, only a real turn does, and it
# is account-level, so any surface's turn activates it. Firing one cheap
# turn at 07:00 pins the day's window boundaries to roughly 07-12-17-22
# instead of wherever the day's first incidental Codex use happens to land.
set -uo pipefail

# $1: path to codex-primary-window-check.py, passed in by me.nix rather than
# found relative to this file -- home-manager deploys each ./scripts/*.nix
# reference to its own isolated nix-store path, so a sibling file cannot be
# found by relative lookup here.
WINDOW_CHECK="$1"

CODEX="$HOME/.local/bin/codex"
# launchd gives this job a bare environment (no ME_HOME) -- fall back to the
# machine-local file fish also reads, since neither is committed to the repo.
SAM_DIR="${ME_HOME:-$(cat "$HOME/.config/me-home" 2>/dev/null || true)}"
ME="$HOME/.local/bin/me"

note() {
  [ -x "$ME" ] && "$ME" note "codex daily poke: $1"
}

if [ ! -x "$CODEX" ]; then
  note "codex binary not found at $CODEX, skipped"
  exit 0
fi

# Run from $HOME, not a repo checkout: Codex loads AGENTS.md from its cwd's
# tree, and $HOME carries only the global one (~/.codex/AGENTS.md, ~15.9KB,
# already accepted loading every turn) with nothing repo-local dragged in on
# top (Petter, 2026-09-10). --skip-git-repo-check because $HOME is not a git
# repo. Bottom of the model/effort ladder, read-only sandbox, one-word
# prompt -- measured 2026-09-10 at 5,620 tokens / ~4.4s wall time from here
# (5,626 from ~/.dotfiles -- the repo's own instructions cost was negligible
# either way; the point is not dragging in whatever a future repo adds).
output=$(cd "$HOME" && "$CODEX" exec -m gpt-6-luna -c model_reasoning_effort=low -s read-only --skip-git-repo-check "hi" 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  note "codex exec exited $status -- $(printf '%s' "$output" | tail -c 300)"
  exit 0
fi

# The turn having exited 0 is not proof it activated anything -- confirm the
# primary window actually reports a reset roughly 5h out. sam runs only from
# inside its own state repo (deliberately), hence the cd.
usage_json=$(cd "$SAM_DIR" 2>&1 && ./bin/sam usage codex --json 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  note "poke ran but sam usage codex failed (exit $status) -- $(printf '%s' "$usage_json" | tail -c 300)"
  exit 0
fi

printf '%s' "$usage_json" | python3 "$WINDOW_CHECK"
if [ $? -ne 0 ]; then
  note "poke ran but the primary window is not ~5h out afterward -- $(printf '%s' "$usage_json" | tail -c 300)"
fi

exit 0
