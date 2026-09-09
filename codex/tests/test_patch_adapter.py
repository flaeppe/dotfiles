"""Exercise Codex patches against the actual shared edit guards."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


class PatchAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.hooks = self.root / "hooks"
        self.hooks.mkdir()
        for name in (
            "protected-path-guard",
            "edit-content-guard",
            "plan-verified-guard",
            "format-after-edit",
        ):
            (self.hooks / name).symlink_to(REPO / "claude/hooks" / name)
        (self.hooks / "patch-adapter.py").symlink_to(
            REPO / "codex/hooks/patch-adapter.py"
        )
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if key
            not in (
                "CLAUDE_SKIP_CONTENT_GUARD",
                "CLAUDE_SKIP_PLAN_GUARD",
                "CLAUDE_NO_AUTOFORMAT",
            )
        }

    def run_hook(self, patch, event="PreToolUse"):
        return subprocess.run(
            [sys.executable, str(self.hooks / "patch-adapter.py")],
            input=json.dumps(
                {
                    "tool_name": "apply_patch",
                    "hook_event_name": event,
                    "cwd": str(self.workspace),
                    "tool_input": {"command": patch},
                }
            ),
            text=True,
            capture_output=True,
            env=self.environment,
            check=False,
        )

    def test_checks_every_file_in_a_patch(self):
        result = self.run_hook(
            "*** Begin Patch\n*** Add File: safe.txt\n+ok\n"
            "*** Add File: .env.local\n+TOKEN=value\n*** End Patch\n"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("holds secrets", result.stderr)

    def test_checks_move_destination(self):
        result = self.run_hook(
            "*** Begin Patch\n*** Update File: safe.txt\n"
            "*** Move to: .env\n@@\n-old\n+new\n*** End Patch\n"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("holds secrets", result.stderr)

    def test_checks_deleted_protected_file(self):
        result = self.run_hook(
            "*** Begin Patch\n*** Delete File: flake.lock\n*** End Patch\n"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("lockfile", result.stderr)

    def test_checks_introduced_content_but_allows_its_removal(self):
        result = self.run_hook(
            "*** Begin Patch\n*** Update File: test_example.py\n@@\n"
            "-def test_example():\n+def test_example() -> None:\n*** End Patch\n"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("pytest", result.stderr)
        result = self.run_hook(
            "*** Begin Patch\n*** Update File: test_example.py\n@@\n"
            "-def test_example() -> None:\n+def test_example():\n*** End Patch\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_malformed_payload_is_not_silently_accepted(self):
        result = self.run_hook("not a patch")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Cannot check apply_patch", result.stderr)

    def test_formats_files_and_returns_codex_context(self):
        ruff = REPO / ".venv/bin/ruff"
        if not ruff.exists():
            self.skipTest("requires the repository's ruff environment")
        binaries = self.workspace / ".venv/bin"
        binaries.mkdir(parents=True)
        (binaries / "ruff").symlink_to(ruff)
        target = self.workspace / "example.py"
        target.write_text('value={"a":1}\n')
        result = self.run_hook(
            '*** Begin Patch\n*** Add File: example.py\n+value={"a":1}\n'
            "*** End Patch\n",
            "PostToolUse",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), 'value = {"a": 1}\n')
        output = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PostToolUse")
        self.assertIn("re-read", output["additionalContext"])


if __name__ == "__main__":
    unittest.main()
