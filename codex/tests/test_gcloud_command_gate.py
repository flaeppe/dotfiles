"""Exercise Codex's gcloud hook adapter."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


class GcloudCommandGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.hooks = Path(self.temporary.name) / "hooks"
        self.hooks.mkdir()
        (self.hooks / "gcloud-command-gate.py").symlink_to(
            REPO / "codex/hooks/gcloud-command-gate.py"
        )
        (self.hooks / "gcloud-command-gate-shared").symlink_to(
            REPO / "claude/hooks/gcloud-command-gate"
        )
        (self.hooks / "shellwords.py").symlink_to(REPO / "claude/hooks/shellwords.py")

    def run_hook(self, command):
        return subprocess.run(
            [sys.executable, str(self.hooks / "gcloud-command-gate.py")],
            input=json.dumps(
                {
                    "tool_name": "Bash",
                    "tool_input": {"command": command},
                }
            ),
            text=True,
            capture_output=True,
            check=False,
        )

    def test_blocks_gcloud(self):
        result = self.run_hook("gcloud projects list")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"decision": "block", "reason": "gcloud requires approval"},
        )

    def test_blocks_logging_with_its_redirect(self):
        result = self.run_hook("gcloud logging read 'resource.type=gce_instance'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["decision"], "block")
        self.assertIn("af log read", json.loads(result.stdout)["reason"])

    def test_ignores_unrelated_commands(self):
        result = self.run_hook("git status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
