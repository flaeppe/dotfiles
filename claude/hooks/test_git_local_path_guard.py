"""Tests for git-local-path-guard.

Runs the guard as a subprocess, exactly as Claude Code's PreToolUse hook
would invoke it, against real repositories in a temp directory with a bare
repository standing in for the remote.

    python3 -m unittest test_git_local_path_guard -v
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "git-local-path-guard"

LEAK = "see _private/plan.md for the details\n"

# No user or system config: a global gpg/sign setting must not reach the fixtures.
GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.com",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.com",
}


class GitLocalPathGuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(os.path.realpath(self._tmp.name))
        self.addCleanup(self._tmp.cleanup)

        self.origin = self.root / "origin.git"
        self.git(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.work = self.clone("work")
        self.commit(self.work, "README.md", "hello\n")
        self.git(self.work, "push", "-q", "origin", "main")

    def git(self, cwd, *args):
        return subprocess.run(
            ["git", *args], cwd=cwd, env=GIT_ENV, check=True, capture_output=True, text=True
        ).stdout

    def clone(self, name):
        self.git(self.root, "clone", "-q", str(self.origin), name)
        return self.root / name

    def commit(self, repo, filename, content):
        path = repo / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.git(repo, "add", filename)
        self.git(repo, "commit", "-q", "-m", "add " + filename)

    def run_guard(self, command, cwd):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)})
        return subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, timeout=10
        )

    def test_denies_staged_local_path(self):
        (self.work / "notes.md").write_text(LEAK)
        self.git(self.work, "add", "notes.md")
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("notes.md: _private/plan.md", result.stderr)

    def test_denies_unpublished_commit_with_local_path(self):
        self.commit(self.work, "notes.md", LEAK)
        result = self.run_guard("git push", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("notes.md: _private/plan.md", result.stderr)

    def test_allows_unpublished_commit_without_local_path(self):
        self.commit(self.work, "notes.md", "nothing local here\n")
        self.assertEqual(self.run_guard("git push", self.work).returncode, 0)

    def test_allows_push_when_nothing_is_unpublished(self):
        self.assertEqual(self.run_guard("git push", self.work).returncode, 0)

    def test_denies_a_local_path_a_later_commit_removes(self):
        self.commit(self.work, "notes.md", LEAK)
        self.commit(self.work, "notes.md", "clean now\n")
        result = self.run_guard("git push", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("notes.md: _private/plan.md", result.stderr)

    def test_allows_push_of_a_branch_rebased_onto_a_moved_default_branch(self):
        self.git(self.work, "switch", "-q", "-c", "feature")
        self.commit(self.work, "feature.md", "feature work\n")
        self.git(self.work, "push", "-q", "-u", "origin", "feature")

        # The default branch moves on with a file the feature branch never touched.
        other = self.clone("other")
        self.commit(other, "docs/leaky.md", LEAK)
        self.git(other, "push", "-q", "origin", "main")

        self.git(self.work, "fetch", "-q", "origin")
        self.git(self.work, "rebase", "-q", "origin/main")

        result = self.run_guard("git push --force-with-lease", self.work)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_denies_a_rebased_branch_that_adds_its_own_local_path(self):
        self.git(self.work, "switch", "-q", "-c", "feature")
        self.commit(self.work, "feature.md", LEAK)
        self.git(self.work, "push", "-q", "-u", "origin", "feature")

        other = self.clone("other")
        self.commit(other, "docs/leaky.md", LEAK)
        self.git(other, "push", "-q", "origin", "main")

        self.git(self.work, "fetch", "-q", "origin")
        self.git(self.work, "rebase", "-q", "origin/main")

        result = self.run_guard("git push --force-with-lease", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("feature.md: _private/plan.md", result.stderr)
        self.assertNotIn("leaky.md", result.stderr)

    def test_ignores_a_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Read", "tool_input": {}, "cwd": str(self.work)})
        result = subprocess.run([str(GUARD)], input=payload, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run([str(GUARD)], input="not json", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
