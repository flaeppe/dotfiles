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
            ["git", *args],
            cwd=cwd,
            env=GIT_ENV,
            check=True,
            capture_output=True,
            text=True,
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

    def run_guard(self, command, cwd, env=None):
        payload = json.dumps(
            {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}
        )
        return subprocess.run(
            [str(GUARD)],
            input=payload,
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
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

    def start_merge_of_a_default_branch_that_added_a_local_path(self):
        self.git(self.work, "switch", "-q", "-c", "feature")
        self.commit(self.work, "feature.md", "feature work\n")

        other = self.clone("other")
        self.commit(other, "docs/leaky.md", LEAK)
        self.git(other, "push", "-q", "origin", "main")

        self.git(self.work, "fetch", "-q", "origin")
        self.git(self.work, "merge", "-q", "--no-commit", "--no-ff", "origin/main")

    def test_allows_a_merge_of_lines_the_other_parent_already_published(self):
        self.start_merge_of_a_default_branch_that_added_a_local_path()
        result = self.run_guard("git commit --no-edit", self.work)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_denies_a_merge_resolution_that_adds_its_own_local_path(self):
        self.start_merge_of_a_default_branch_that_added_a_local_path()
        (self.work / "resolution.md").write_text(LEAK)
        self.git(self.work, "add", "resolution.md")
        result = self.run_guard("git commit --no-edit", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("resolution.md: _private/plan.md", result.stderr)
        self.assertNotIn("leaky.md", result.stderr)

    def test_allows_a_push_in_a_repo_with_no_remote(self):
        lonely = self.root / "lonely"
        self.git(self.root, "init", "-q", "-b", "main", str(lonely))
        self.commit(lonely, "notes.md", LEAK)
        result = self.run_guard("git push", lonely)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_allows_a_commit_in_a_repo_with_no_remote(self):
        lonely = self.root / "lonely"
        self.git(self.root, "init", "-q", "-b", "main", str(lonely))
        (lonely / "notes.md").write_text(LEAK)
        self.git(lonely, "add", "notes.md")
        result = self.run_guard("git commit -m wip", lonely)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_allows_a_path_limited_commit_beside_other_staged_leaks(self):
        self.commit(self.work, "clean.md", "clean\n")
        (self.work / "clean.md").write_text("clean again\n")
        (self.work / "other-session.md").write_text(LEAK)
        self.git(self.work, "add", "other-session.md")
        result = self.run_guard("git commit -m wip -- clean.md", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_denies_a_path_limited_commit_of_a_leaking_file(self):
        self.commit(self.work, "notes.md", "clean\n")
        (self.work / "notes.md").write_text(LEAK)
        result = self.run_guard("git commit -m wip -- notes.md", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("notes.md: _private/plan.md", result.stderr)

    def test_resolves_a_path_limited_commit_from_a_subdirectory(self):
        self.commit(self.work, "docs/notes.md", "clean\n")
        (self.work / "docs" / "notes.md").write_text(LEAK)
        result = self.run_guard("git commit -m wip -- notes.md", self.work / "docs")
        self.assertEqual(result.returncode, 2)

    def test_checks_the_repo_a_leading_cd_names_not_the_session_cwd(self):
        self.commit(self.work, "notes.md", LEAK)
        scratch = self.clone("scratch")
        result = self.run_guard("cd %s && git push" % scratch, self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_a_refusal_says_the_whole_command_did_not_run(self):
        (self.work / "notes.md").write_text(LEAK)
        self.git(self.work, "add", "notes.md")
        result = self.run_guard("echo edit && git commit -m wip", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("no step of it ran", result.stderr)

    def test_allows_the_call_when_git_outlives_the_timeout(self):
        self.commit(self.work, "notes.md", LEAK)
        slow_git = self.root / "bin" / "git"
        slow_git.parent.mkdir()
        slow_git.write_text("#!/bin/sh\nexec sleep 30\n")
        slow_git.chmod(0o755)
        env = {
            **os.environ,
            "PATH": str(slow_git.parent) + os.pathsep + os.environ["PATH"],
            "GIT_LOCAL_PATH_GUARD_TIMEOUT": "0.5",
        }
        result = self.run_guard("git push", self.work, env=env)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stderr.strip(),
            "git-local-path-guard: git exceeded 0.5s; allowing the call",
        )

    def test_ignores_a_git_push_quoted_inside_a_heredoc_body(self):
        self.commit(self.work, "notes.md", LEAK)
        command = (
            "cat > plan.md <<'EOF'\n"
            "Sam's note:\n"
            "`git push --force-with-lease=x:y origin HEAD:refs/heads/x`\n"
            "EOF\n"
        )
        result = self.run_guard(command, self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_scans_a_push_that_follows_a_heredoc(self):
        self.commit(self.work, "notes.md", LEAK)
        command = "cat > plan.md <<'EOF'\nSam's note\nEOF\ngit push"
        self.assertEqual(self.run_guard(command, self.work).returncode, 2)

    def test_ignores_a_push_in_a_dash_heredoc_closed_by_an_indented_tag(self):
        self.commit(self.work, "notes.md", LEAK)
        command = "cat <<-EOF\n\tgit push\n\tEOF\n"
        self.assertEqual(self.run_guard(command, self.work).returncode, 0)

    def write_allowlist(self, text):
        allow = self.work / ".claude" / "local-path-allow"
        allow.parent.mkdir(exist_ok=True)
        allow.write_text(text)

    def stage(self, filename, content):
        path = self.work / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.git(self.work, "add", filename)

    def test_a_path_entry_exempts_every_line_under_it(self):
        self.write_allowlist("docs/\n")
        self.stage("docs/notes.md", LEAK + "also _private/other.md\n")
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_a_pattern_entry_exempts_only_the_lines_it_matches(self):
        self.write_allowlist("docs/:^see _private/plan\\.md\n")
        self.stage("docs/notes.md", LEAK)
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_a_matching_path_with_a_non_matching_line_is_refused(self):
        self.write_allowlist("docs/:^see _private/plan\\.md\n")
        self.stage("docs/notes.md", LEAK + "also _private/other.md\n")
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("_private/other.md", result.stderr)
        self.assertNotIn("_private/plan.md", result.stderr)

    def test_a_pattern_entry_does_not_exempt_other_paths(self):
        self.write_allowlist("docs/:_private\n")
        self.stage("src/notes.md", LEAK)
        self.assertEqual(self.run_guard("git commit -m wip", self.work).returncode, 2)

    def assert_allowlist_exempts_nothing(self, text):
        if text is not None:
            self.write_allowlist(text)
        self.stage("docs/notes.md", LEAK)
        self.assertEqual(self.run_guard("git commit -m wip", self.work).returncode, 2)

    def test_a_missing_allowlist_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing(None)

    def test_an_empty_allowlist_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing("")

    def test_a_comment_only_allowlist_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing("# docs/\n\n")

    def test_an_entry_with_a_trailing_space_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing("docs/ \n")

    def test_an_entry_with_an_empty_pattern_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing("docs/:\n")

    def test_an_entry_with_an_empty_path_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing(":_private\n")

    def test_an_entry_with_an_invalid_pattern_exempts_nothing(self):
        self.assert_allowlist_exempts_nothing("docs/:(\n")

    def test_a_marked_line_in_a_test_file_passes(self):
        self.stage("notes_test.go", 'path := "_private/plan.md" // local-path-ok\n')
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_an_unmarked_line_in_a_test_file_is_refused(self):
        self.stage("notes_test.go", 'path := "_private/plan.md"\n')
        self.assertEqual(self.run_guard("git commit -m wip", self.work).returncode, 2)

    def test_a_marked_line_outside_a_test_file_is_refused(self):
        self.stage("notes.go", 'path := "_private/plan.md" // local-path-ok\n')
        self.assertEqual(self.run_guard("git commit -m wip", self.work).returncode, 2)

    def test_a_marker_exempts_its_own_line_only(self):
        self.stage(
            "test_notes.py",
            "a = '_private/a.md'  # local-path-ok\nb = '_private/b.md'\n",
        )
        result = self.run_guard("git commit -m wip", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("_private/b.md", result.stderr)
        self.assertNotIn("_private/a.md", result.stderr)

    def test_judges_a_commit_on_the_index_its_own_add_leaves(self):
        (self.work / "notes.md").write_text(LEAK)
        result = self.run_guard("git add notes.md && git commit -m wip", self.work)
        self.assertEqual(result.returncode, 2)
        self.assertIn("notes.md: _private/plan.md", result.stderr)

    def test_an_add_of_a_clean_file_does_not_trip_a_leaking_one_left_unstaged(self):
        (self.work / "notes.md").write_text(LEAK)
        (self.work / "clean.md").write_text("clean\n")
        result = self.run_guard("git add clean.md && git commit -m wip", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_an_add_in_the_command_leaves_the_real_index_untouched(self):
        (self.work / "notes.md").write_text(LEAK)
        self.run_guard("git add notes.md && git commit -m wip", self.work)
        self.assertEqual(self.git(self.work, "diff", "--cached", "--name-only"), "")

    def test_a_failing_add_leaves_the_commit_judged_on_the_current_index(self):
        self.stage("clean.md", "clean\n")
        result = self.run_guard("git add no-such-file && git commit -m wip", self.work)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_an_add_after_the_commit_is_not_applied_to_it(self):
        (self.work / "notes.md").write_text(LEAK)
        result = self.run_guard(
            "git commit --allow-empty -m wip && git add notes.md", self.work
        )
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_replays_an_add_in_the_directory_a_cd_names(self):
        (self.work / "docs").mkdir()
        (self.work / "docs" / "notes.md").write_text(LEAK)
        scratch = self.clone("scratch")
        result = self.run_guard(
            "cd %s/docs && git add notes.md && git commit -m wip" % self.work, scratch
        )
        self.assertEqual(result.returncode, 2)

    def test_ignores_a_non_bash_tool(self):
        payload = json.dumps(
            {"tool_name": "Read", "tool_input": {}, "cwd": str(self.work)}
        )
        result = subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run(
            [str(GUARD)], input="not json", capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
