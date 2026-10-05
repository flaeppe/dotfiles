"""Exercise Codex's gcloud hook adapter against stand-in shared guards."""

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

    def install_guard(self, stdout="", status=0):
        """Install a shared guard that prints stdout and exits with status."""
        guard = self.hooks / "gcloud-command-gate-shared"
        guard.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            f"sys.stdout.write({stdout!r})\n"
            f"sys.exit({status})\n"
        )
        guard.chmod(0o755)

    def verdict(self, decision, reason):
        return json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision,
                    "permissionDecisionReason": reason,
                }
            }
        )

    def run_hook(self, command="gcloud projects list"):
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

    def test_blocks_an_ask_verdict_with_its_reason(self):
        self.install_guard(self.verdict("ask", "gcloud requires approval"))
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"decision": "block", "reason": "gcloud requires approval"},
        )

    def test_blocks_a_deny_verdict_with_its_reason(self):
        self.install_guard(self.verdict("deny", "use the read-only wrapper"))
        result = self.run_hook("gcloud logging read 'resource.type=gce_instance'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"decision": "block", "reason": "use the read-only wrapper"},
        )

    def test_ignores_a_guard_with_no_verdict(self):
        self.install_guard()
        result = self.run_hook("git status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_ignores_an_allow_verdict(self):
        self.install_guard(self.verdict("allow", "fine"))
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_refuses_output_it_cannot_parse(self):
        self.install_guard("not json")
        result = self.run_hook()
        self.assertEqual(result.returncode, 2)

    def test_passes_a_failing_guard_status_through(self):
        self.install_guard(status=3)
        result = self.run_hook()
        self.assertEqual(result.returncode, 3)


if __name__ == "__main__":
    unittest.main()
