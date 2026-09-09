#!/usr/bin/python3
"""Adapt Codex apply_patch events to the shared file-edit hooks."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def patch_edits(patch: str) -> list[dict[str, str]]:
    """Return every touched path and its introduced text, including move targets."""
    edits: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in patch.splitlines(keepends=True):
        for operation in ("Add", "Update", "Delete"):
            prefix = f"*** {operation} File: "
            if line.startswith(prefix):
                current = {
                    "file_path": line[len(prefix) :].rstrip("\r\n"),
                    "new_string": "",
                }
                edits.append(current)
                break
        else:
            if line.startswith("*** Move to: "):
                if current is None:
                    raise ValueError("Move without a file header")
                current = {
                    "file_path": line[len("*** Move to: ") :].rstrip("\r\n"),
                    "new_string": "",
                }
                edits.append(current)
            elif line.startswith("+") and current is not None:
                current["new_string"] += line[1:]
    if not edits:
        raise ValueError("No file paths found in apply_patch payload")
    return edits


def main() -> int:
    payload = json.load(sys.stdin)
    if payload.get("tool_name") != "apply_patch":
        return 0
    event = payload.get("hook_event_name")
    if event not in ("PreToolUse", "PostToolUse"):
        return 0
    edits = patch_edits(payload["tool_input"]["command"])
    hooks = ("protected-path-guard", "edit-content-guard", "plan-verified-guard")
    if event == "PostToolUse":
        hooks = ("format-after-edit",)
    directory = Path(__file__).parent
    cwd = payload.get("cwd") or os.getcwd()
    notices: list[str] = []
    for edit in edits:
        if not os.path.isabs(edit["file_path"]):
            edit["file_path"] = os.path.join(cwd, edit["file_path"])
        adapted = {**payload, "tool_name": "Edit", "tool_input": edit}
        for hook in hooks:
            result = subprocess.run(
                [sys.executable, str(directory / hook)],
                input=json.dumps(adapted),
                text=True,
                capture_output=True,
                cwd=cwd,
                timeout=50,
            )
            if result.returncode:
                if event == "PreToolUse":
                    print(
                        result.stderr or f"Edit guard failed: {hook}", file=sys.stderr
                    )
                    return 2
                notices.append(result.stderr.strip())
    if notices:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PostToolUse",
                        "additionalContext": "\n".join(notices),
                    }
                }
            )
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (
        KeyError,
        TypeError,
        ValueError,
        OSError,
        subprocess.SubprocessError,
    ) as error:
        print(f"Cannot check apply_patch: {error}", file=sys.stderr)
        sys.exit(2)
