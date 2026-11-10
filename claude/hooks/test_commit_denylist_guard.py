"""Tests for commit-denylist-guard.

Runs the guard as a subprocess with $HOME pointing at a scratch tree, so the
denylist it reads is a fixture.

    python3 -m unittest test_commit_denylist_guard -v
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "commit-denylist-guard"

TERM = "forbiddenterm"


class CommitDenylistGuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = Path(os.path.realpath(self._tmp.name))
        self.repo = self.home / "repo"
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        config = self.home / ".config"
        config.mkdir()
        (config / "git-banned-words").write_text("%s\nrepo:%s\n" % (TERM, self.repo))

    def run_guard(self, command, cwd=None):
        payload = json.dumps(
            {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd or self.repo)}
        )
        return subprocess.run(
            ["/usr/bin/python3", str(GUARD)],
            input=payload,
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, "HOME": str(self.home)},
        )

    def decision(self, command, cwd=None):
        out = self.run_guard(command, cwd).stdout
        return json.loads(out)["hookSpecificOutput"] if out else None

    def test_denies_a_term_in_the_commit_message_and_names_it(self):
        verdict = self.decision("git commit -m 'about %s'" % TERM.upper())
        self.assertEqual(verdict["permissionDecision"], "deny")
        self.assertIn("`%s`" % TERM.upper(), verdict["permissionDecisionReason"])

    def test_denies_a_term_in_a_heredoc_message(self):
        command = "git commit -m \"$(cat <<'EOF'\nabout %s\nEOF\n)\"" % TERM
        self.assertEqual(self.decision(command)["permissionDecision"], "deny")

    def test_denies_a_term_in_a_message_piped_from_a_heredoc(self):
        command = "git commit -F - <<'EOF'\nabout %s\nEOF" % TERM
        self.assertEqual(self.decision(command)["permissionDecision"], "deny")

    def test_allows_a_clean_commit_chained_after_a_command_naming_the_term(self):
        self.assertIsNone(self.decision("ls /tmp/%s && git commit -m clean" % TERM))

    def test_allows_a_term_in_a_repo_that_has_not_opted_in(self):
        elsewhere = self.home / "elsewhere"
        subprocess.run(["git", "init", "-q", str(elsewhere)], check=True)
        self.assertIsNone(self.decision("git commit -m %s" % TERM, cwd=elsewhere))

    def test_ignores_a_command_that_is_not_a_commit(self):
        self.assertIsNone(self.decision("echo %s" % TERM))


if __name__ == "__main__":
    unittest.main()
