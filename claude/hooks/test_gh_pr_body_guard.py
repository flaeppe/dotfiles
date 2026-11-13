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
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "gh-pr-body-guard"

MARKER = "<!-- pr:v1 -->"
CLEAN_BODY = "A one-line fix for a real bug.\n\n**Push back:** nothing risky here.\n" + MARKER


class GhPrBodyGuardTest(unittest.TestCase):
    def run_guard(self, command, cwd="/tmp", env=None):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd})
        return subprocess.run(
            [str(GUARD)],
            input=payload,
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, **(env or {})},
        )

    def write_body_file(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(text)
        self.addCleanup(Path(handle.name).unlink)
        return handle.name

    def run_guard_with_body(self, flag, body, cwd="/tmp"):
        command = 'gh pr create --title t %s "%s"' % (flag, body)
        return self.run_guard(command, cwd=cwd)

    def run_guard_with_heredoc_body(self, body, delimiter="'BODY'"):
        """The command the pr skill's template produces."""
        bare = delimiter.strip("'\"")
        command = 'gh pr create --title t --body "$(cat <<%s\n%s\n%s\n)"' % (delimiter, body, bare)
        return self.run_guard(command)

    def test_allows_a_clean_body(self):
        result = self.run_guard_with_body("--body", CLEAN_BODY)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_the_skill_template_heredoc(self):
        result = self.run_guard_with_heredoc_body(CLEAN_BODY)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_a_heredoc_body_missing_the_marker(self):
        result = self.run_guard_with_heredoc_body("A fix, no marker.\n\n**Push back:** none.")
        self.assertEqual(result.returncode, 2)
        self.assertIn("load the pr skill", result.stderr.lower())

    def test_lints_a_heredoc_body(self):
        body = "## Testing\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_heredoc_body(body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("## Testing", result.stderr)

    def test_refuses_a_heredoc_with_an_unquoted_delimiter(self):
        # Unquoted, the shell expands the text, so the hook cannot know what gh receives.
        result = self.run_guard_with_heredoc_body(CLEAN_BODY, delimiter="BODY")
        self.assertEqual(result.returncode, 2)

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
        body = "## Testing\nRan the suite.\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("## Testing", result.stderr)

    def test_allows_a_headed_body_with_summary_first(self):
        paragraph = " ".join(["word"] * 60)
        sections = ("## Summary", "## Context", "## Evidence")
        body = "\n\n".join("%s\n%s" % (heading, paragraph) for heading in sections)
        body += "\n\n## Push back on\nThe cap.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_a_paragraph_over_the_word_cap(self):
        paragraph = " ".join(["word"] * 81)
        body = paragraph + "\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("81 words", result.stderr)

    def test_counts_a_soft_wrapped_paragraph_as_one(self):
        wrapped = "\n".join(" ".join(["word"] * 10) for _ in range(9))
        body = wrapped + "\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("90 words", result.stderr)

    def test_refuses_a_body_over_the_word_cap(self):
        paragraphs = "\n\n".join(" ".join(["word"] * 70) for _ in range(7))
        body = paragraphs + "\n\n**Push back:** none.\n" + MARKER
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 2)
        self.assertIn("493 words", result.stderr)

    def test_allows_list_items_tables_and_code_beyond_the_paragraph_cap(self):
        items = "\n".join("- " + " ".join(["word"] * 30) for _ in range(5))
        table = "| area | lines |\n|---|---|\n" + "\n".join("| row %d | %d |" % (i, i) for i in range(20))
        code = "```\n" + "\n".join(" ".join(["token"] * 10) for _ in range(10)) + "\n```"
        body = "\n\n".join(("One line of prose.", items, table, code, "**Push back:** none.\n" + MARKER))
        result = self.run_guard_with_body("--body", body)
        self.assertEqual(result.returncode, 0, result.stderr)

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

    def test_allows_pr_edit_that_sets_no_body(self):
        for command in (
            "gh pr edit 1 --add-reviewer octocat",
            "gh pr edit 1 --title 'a new title'",
        ):
            result = self.run_guard(command)
            self.assertEqual(result.returncode, 0, "%s: %s" % (command, result.stderr))

    def test_refuses_pr_edit_with_an_unmarked_body(self):
        result = self.run_guard('gh pr edit 1 --add-reviewer octocat --body "no marker"')
        self.assertEqual(result.returncode, 2)

    def test_checks_body_file_named_by_a_variable_the_command_assigns(self):
        clean = self.write_body_file(CLEAN_BODY)
        unmarked = self.write_body_file("A fix, no marker.\n\n**Push back:** none.")
        allowed = self.run_guard('BODY_PATH=%s; gh api -X PATCH repos/example/example/pulls/1 -F "body=@$BODY_PATH"' % clean)
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        refused = self.run_guard("export BODY_PATH=%s && gh api -X PATCH repos/example/example/pulls/1 -F body=@$BODY_PATH" % unmarked)
        self.assertEqual(refused.returncode, 2)

    def test_checks_body_file_named_by_a_variable_in_the_hook_environment(self):
        clean = self.write_body_file(CLEAN_BODY)
        unmarked = self.write_body_file("A fix, no marker.\n\n**Push back:** none.")
        allowed = self.run_guard("gh pr edit 1 --body-file ${GUARD_TEST_BODY}", env={"GUARD_TEST_BODY": clean})
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        refused = self.run_guard("gh pr edit 1 --body-file $GUARD_TEST_BODY", env={"GUARD_TEST_BODY": unmarked})
        self.assertEqual(refused.returncode, 2)

    def test_lets_through_a_body_file_variable_nothing_defines(self):
        result = self.run_guard("gh pr edit 1 --body-file $GUARD_TEST_UNDEFINED")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("only the shell can resolve", result.stderr)

    def test_lets_through_a_body_file_from_command_substitution(self):
        for command in (
            'gh pr create --title t --body-file "$(mktemp)"',
            "gh pr create --title t --body-file $(mktemp)",
        ):
            result = self.run_guard(command)
            self.assertEqual(result.returncode, 0, "%s: %s" % (command, result.stderr))
            self.assertIn("only the shell can resolve", result.stderr)

    def test_lets_through_a_variable_path_to_a_file_not_yet_written(self):
        result = self.run_guard("BODY_PATH=/no/such/file.md; gh api -X PATCH repos/example/example/pulls/1 -F body=@$BODY_PATH")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("only the shell can resolve", result.stderr)

    def test_lets_through_an_api_body_file_variable_nothing_defines(self):
        command = 'gh api -X PATCH repos/example/example/pulls/1 -F "body=@$GUARD_TEST_UNDEFINED"'
        result = self.run_guard(command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_body_file_stdin(self):
        result = self.run_guard("gh pr create --title t --body-file -")
        self.assertEqual(result.returncode, 2)

    def test_resolves_a_relative_body_file_against_the_commands_cd_target(self):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        (Path(directory) / "body.md").write_text(CLEAN_BODY)
        result = self.run_guard("cd %s && gh api -X PATCH repos/example/example/pulls/1 -F body=@body.md" % directory)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_resolves_a_relative_body_file_against_the_hook_cwd_without_a_cd(self):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        (Path(directory) / "body.md").write_text(CLEAN_BODY)
        result = self.run_guard("gh pr create --title t --body-file body.md", cwd=directory)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_resolves_a_relative_api_body_file_against_the_hook_cwd(self):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        (Path(directory) / "body.md").write_text(CLEAN_BODY)
        command = "gh api -X PATCH repos/example/example/pulls/1 -F body=@body.md"
        result = self.run_guard(command, cwd=directory)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refusal_names_the_forms_the_guard_can_read(self):
        result = self.run_guard("gh pr create --title t --body-file /no/such/file.md")
        self.assertIn("quoted delimiter", result.stderr)
        self.assertIn("/absolute/path", result.stderr)

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

    def test_refuses_a_pr_write_chained_with_another_command(self):
        # Each way a second command can share the call: cd, pipe, `;`, `&&`, assignment, heredoc.
        chained = {
            "leading cd": "cd /tmp/repo && gh pr ready 56 --repo example/example",
            "pipe": "gh pr ready 56 --repo example/example | tail -3",
            "semicolon": "gh pr edit 1 --add-reviewer octocat; gh pr view 1",
            "variable assignment": "S=/tmp/body.md && gh pr create --title t --body-file $S",
            "heredoc file write": "cat > /tmp/body.md <<'EOF'\n%s\nEOF\ngh pr create --title t --body-file /tmp/body.md" % CLEAN_BODY,
            "heredoc file write then &&": "cat > /tmp/body.md <<'EOF'\n%s\nEOF\n&& gh pr create --title t --body-file /tmp/body.md" % CLEAN_BODY,
            "comment after a read": "gh pr view 1 && gh pr comment 1 --body hi",
            "inline assignment": "GH_TOKEN=x gh pr ready 56",
        }
        for form, command in chained.items():
            result = self.run_guard(command)
            self.assertEqual(result.returncode, 2, "%s: %s" % (form, result.stderr))
            self.assertIn("own Bash call", result.stderr, form)

    def test_allows_a_lone_pr_write(self):
        body = self.write_body_file(CLEAN_BODY)
        lone = (
            "gh pr ready 56 --repo example/example",
            "gh pr comment 1 --repo example/example --body-file %s" % body,
            "gh pr edit 1 --repo example/example --add-reviewer octocat",
            "gh pr create --repo example/example --title t --body-file %s" % body,
            "gh pr ready 56 --repo example/example 2>&1",
            'gh pr comment 1 --body "a && b; c | d"',
        )
        for command in lone:
            result = self.run_guard(command)
            self.assertEqual(result.returncode, 0, "%s: %s" % (command, result.stderr))

    def test_allows_chained_commands_that_write_no_pr(self):
        for command in (
            "cd /tmp && gh pr view 1 | tail -3",
            "cd /tmp && gh pr checks 1 --watch",
        ):
            result = self.run_guard(command)
            self.assertEqual(result.returncode, 0, "%s: %s" % (command, result.stderr))

    def test_ignores_a_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "x"}})
        result = subprocess.run([str(GUARD)], input=payload, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run([str(GUARD)], input="not json", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
