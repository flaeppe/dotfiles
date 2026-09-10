#!/usr/bin/python3
"""Adapt the shared gcloud guard to Codex's blocking hook response."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def shared_output(payload: str) -> tuple[dict[str, Any] | None, str, int]:
    """Run the shared guard and parse its JSON response."""
    shared_guard = Path(__file__).with_name("gcloud-command-gate-shared")
    result = subprocess.run(
        [str(shared_guard)],
        input=payload,
        text=True,
        capture_output=True,
        check=False,
    )
    if not result.stdout.strip():
        return None, result.stderr, result.returncode
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        print(f"Cannot parse gcloud guard response: {error}", file=sys.stderr)
        return None, result.stderr, 2
    if not isinstance(output, dict):
        print("gcloud guard response must be an object", file=sys.stderr)
        return None, result.stderr, 2
    return output, result.stderr, result.returncode


def main() -> int:
    output, stderr, status = shared_output(sys.stdin.read())
    if stderr:
        print(stderr, file=sys.stderr, end="")
    if status:
        return status
    if output is None:
        return 0

    hook_output = output.get("hookSpecificOutput", {})
    if not isinstance(hook_output, dict):
        print("gcloud guard hook output must be an object", file=sys.stderr)
        return 2
    decision = hook_output.get("permissionDecision")
    if decision not in ("ask", "deny"):
        return 0
    reason = hook_output.get("permissionDecisionReason")
    if not isinstance(reason, str) or not reason:
        print("gcloud guard did not provide a decision reason", file=sys.stderr)
        return 2
    print(json.dumps({"decision": "block", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
