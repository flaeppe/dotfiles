"""Tests for gh-pr-body-guard.

Runs the guard as a subprocess, exactly as Claude Code's PreToolUse hook
would invoke it. Bodies are embedded as real, unescaped newlines inside a
double-quoted shell argument and the whole payload is JSON-encoded exactly
once -- double-encoding (escaping the body for the shell, then JSON-encoding
that already-escaped text) would turn real newlines into literal `\\n` text
by the time the guard sees them.

    python3 -m unittest test_gh_pr_body_guard -v
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "gh-pr-body-guard"

MARKER = "<!-- pr:v1 -->"
CLEAN_BODY = "A one-line fix for a real bug.\n\n**Push back:** nothing risky here.\n" + MARKER


class GhPrBodyGuardTest(unittest.TestCase):
    def run_guard(self, command, cwd="/tmp"):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd})
        return subprocess.run([str(GUARD)], input=payload, capture_output=True, text=True, timeout=10)

    def run_guard_with_body(self, flag, body, cwd="/tmp"):
        command = 'gh pr create --title t %s "%s"' % (flag, body)
        return self.run_guard(command, cwd=cwd)

    def test_allows_a_clean_body(self):
        result = self.run_guard_with_body("--body", CLEAN_BODY)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_missing_marker(self):
        result = self.run_guard_with_body("--body", "A fix, no marker.\n\n**Push back:** none.")
        self.assertEqual(result.returncode, 2)
        self.assertIn("load the pr skill", result.stderr.lower())
        self.assertNotIn(MARKER, result.stderr)

    def test_refuses_fill(self):
        result = self.run_guard("gh pr create --title t --fill")
        self.assertEqual(result.returncode, 2)
        self.assertIn("load the pr skill", result.stderr.lower())

    def test_refuses_no_body_at_all(self):
        result = self.run_guard("gh pr create --title t")
        self.assertEqual(result.returncode, 2)

    def test_refuses_local_only_path(self):
        body = "See ~/.plan/example/notes.md for the full trace.\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn(".plan/", result.stderr)

    def test_refuses_forbidden_heading(self):
        body = "## Summary\nDid a thing.\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("## Summary", result.stderr)

    def test_refuses_over_line_cap(self):
        lines = "\n".join("line %d" % i for i in range(13))
        body = lines + "\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("line cap", result.stderr)

    def test_refuses_missing_push_back_line(self):
        body = "Just a fix, nothing more to say.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("push back", result.stderr.lower())

    def test_allows_body_file_with_clean_content(self):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(CLEAN_BODY)
            path = handle.name
        try:
            result = self.run_guard("gh pr create --title t --body-file %s" % path)
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            Path(path).unlink()

    def test_refuses_body_file_stdin(self):
        result = self.run_guard("gh pr create --title t --body-file -")
        self.assertEqual(result.returncode, 2)

    def test_refuses_body_file_that_does_not_exist(self):
        result = self.run_guard("gh pr create --title t --body-file /no/such/file.md")
        self.assertEqual(result.returncode, 2)

    def test_allows_api_patch_on_pulls_with_clean_body_field(self):
        body = "A one-line fix.\n\n**Push back:** none.\n" + MARKER
        command = 'gh api -X PATCH repos/example/example/pulls/1 -f "body=%s"' % body
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_api_patch_on_pulls_missing_marker(self):
        command = 'gh api -X PATCH repos/example/example/pulls/1 -f "body=no marker here"'
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 2)

    def test_allows_api_get_on_pulls(self):
        result = self.run_guard("gh api repos/example/example/pulls/1")
        self.assertEqual(result.returncode, 0)

    def test_allows_pr_view_untouched(self):
        result = self.run_guard("gh pr view 123")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_pr_list_untouched(self):
        result = self.run_guard("gh pr list")
        self.assertEqual(result.returncode, 0)

    def test_allows_review_comment_reply_endpoint(self):
        command = 'gh api repos/example/example/pulls/1/comments/2/replies -f "body=no marker, not a PR body"'
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_review_comment_reply_via_in_reply_to(self):
        command = (
            'gh api repos/example/example/pulls/1/comments '
            '-f in_reply_to=2 -f "body=no marker, not a PR body"'
        )
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_pr_comment(self):
        result = self.run_guard('gh pr comment 1 --body "no marker, not a PR body"')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ignores_a_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "x"}})
        result = subprocess.run([str(GUARD)], input=payload, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run([str(GUARD)], input="not json", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
