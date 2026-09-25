"""Tests for gcloud-command-gate.

Runs the guard as a subprocess, exactly as Claude Code's PreToolUse hook
would invoke it. The guard always exits 0 and reports its verdict as JSON on
stdout (or prints nothing for no verdict), unlike the stderr/exit-code guards
elsewhere in this directory.

    python3 -m unittest test_gcloud_command_gate -v
"""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "gcloud-command-gate"


class GcloudCommandGateTest(unittest.TestCase):
    def run_guard(self, command):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
        return subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, timeout=10
        )

    def decision(self, command):
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 0, result.stderr)
        if not result.stdout.strip():
            return None, None
        output = json.loads(result.stdout)["hookSpecificOutput"]
        return output["permissionDecision"], output["permissionDecisionReason"]

    def test_denies_gcloud_monitoring(self):
        decision, reason = self.decision("gcloud monitoring time-series list")
        self.assertEqual(decision, "deny")
        self.assertIn("af metrics query", reason)

    def test_denies_curl_with_embedded_gcloud_token_against_monitoring(self):
        command = (
            'curl -H "Authorization: Bearer $(gcloud auth print-access-token)" '
            "'https://monitoring.googleapis.com/v3/projects/p/timeSeries?filter=x'"
        )
        decision, reason = self.decision(command)
        self.assertEqual(decision, "deny")
        self.assertIn("af metrics query", reason)

    def test_denies_wget_against_logging(self):
        decision, reason = self.decision(
            "wget https://logging.googleapis.com/v2/entries:list"
        )
        self.assertEqual(decision, "deny")
        self.assertIn("af log read", reason)

    def test_denies_a_url_quoted_in_a_commit_message(self):
        # Ceiling: the host match is a plain substring test, so text that
        # merely mentions the host denies too -- see the guard's docstring.
        decision, reason = self.decision(
            'git commit -m "curl https://monitoring.googleapis.com"'
        )
        self.assertEqual(decision, "deny")
        self.assertIn("af metrics query", reason)

    def test_still_denies_gcloud_logging(self):
        decision, reason = self.decision(
            "gcloud logging read 'resource.type=gce_instance'"
        )
        self.assertEqual(decision, "deny")
        self.assertIn("af log read", reason)

    def test_still_asks_for_other_gcloud_commands(self):
        decision, _reason = self.decision("gcloud sql instances describe x")
        self.assertEqual(decision, "ask")

    def test_ignores_curl_against_an_unrelated_host(self):
        decision, _reason = self.decision("curl https://example.com")
        self.assertIsNone(decision)

    def test_ignores_a_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "x"}})
        result = subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run(
            [str(GUARD)], input="not json", capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
