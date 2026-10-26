"""Tests for log-assertion-check.

Detection is exercised in-process on fixture snippets (log_assertion_fixtures/,
kept out of *.py so the hook never reads them as tests). The hook protocol is
exercised as a subprocess, exactly as Claude Code's PreToolUse hook and the git
pre-commit hook would invoke it.

    python3 -m unittest test_log_assertion_check -v
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

HERE = Path(__file__).parent
HOOK = HERE / "log-assertion-check"
FIXTURES = HERE / "log_assertion_fixtures"

sys.path.insert(0, str(HERE))
_spec = importlib.util.spec_from_loader("log_assertion_check", SourceFileLoader("log_assertion_check", str(HOOK)))
detector = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(detector)


def fixture(name: str) -> str:
    return (FIXTURES / f"{name}.fixture").read_text()


class DetectionTest(unittest.TestCase):
    def assert_flags(self, path: str, name: str, pattern: str, line: int) -> None:
        hits = detector.find_hits(path, fixture(name))
        self.assertEqual([(hit.pattern, hit.line) for hit in hits], [(pattern, line)])

    def test_flags_a_python_caplog_read(self):
        self.assert_flags("tests/test_settle.py", "python_caplog", "caplog", 9)

    def test_flags_python_assert_logs(self):
        self.assert_flags("tests/test_settle.py", "python_assert_logs", "assertLogs", 8)

    def test_flags_a_python_structlog_capture_read(self):
        self.assert_flags("tests/test_settle.py", "python_capture_logs", "capture_logs", 9)

    def test_flags_a_python_log_capture_read(self):
        self.assert_flags("tests/test_settle.py", "python_log_capture", "LogCapture", 9)

    def test_flags_a_python_logger_mock_assertion(self):
        self.assert_flags("tests/test_settle.py", "python_logger_mock", "logger_mock", 9)

    def test_flags_a_go_buffer_read(self):
        self.assert_flags("billing/settle_test.go", "go_buffer", "log_buffer", 17)

    def test_flags_a_go_logrus_hook_read(self):
        self.assert_flags("billing/settle_test.go", "go_logrus_hook", "logrus_hook", 14)

    def test_flags_a_go_zap_observer_read(self):
        self.assert_flags("billing/settle_test.go", "go_zap_observer", "zap_observer", 15)

    def test_flags_a_typescript_console_spy(self):
        self.assert_flags("src/settle.test.ts", "typescript_spy_console", "spy_logger", 6)

    def test_flags_a_typescript_logger_spy_declared_over_several_lines(self):
        self.assert_flags("src/settle.test.ts", "typescript_spy_logger_multiline", "spy_logger", 8)

    def test_flags_a_typescript_fake_logger(self):
        self.assert_flags("src/settle.test.ts", "typescript_fake_logger", "fake_logger", 6)

    def test_flags_a_typescript_log_stream_sink(self):
        self.assert_flags("src/settle.test.ts", "typescript_sink_push", "sink_push", 9)

    def test_ignores_a_business_outcome_assertion_next_to_a_logging_fixture(self):
        self.assertEqual(detector.find_hits("tests/test_settle.py", fixture("python_business_outcome")), [])

    def test_ignores_command_output_captured_through_set_output(self):
        self.assertEqual(detector.find_hits("billing/receipt_test.go", fixture("go_command_output")), [])

    def test_ignores_a_push_collector_that_is_not_a_log_stream(self):
        self.assertEqual(detector.find_hits("src/settle.test.ts", fixture("typescript_event_collector")), [])

    def test_ignores_a_console_spy_that_only_silences_output(self):
        self.assertEqual(detector.find_hits("src/settle.test.ts", fixture("typescript_silenced_console")), [])

    def test_ignores_files_that_are_not_tests(self):
        self.assertEqual(detector.find_hits("billing/settle.py", fixture("python_caplog")), [])
        self.assertEqual(detector.find_hits("src/settle.ts", fixture("typescript_spy_console")), [])
        self.assertEqual(detector.find_hits("billing/settle.go", fixture("go_buffer")), [])


class OnlyNewHitsTest(unittest.TestCase):
    path = "tests/test_settle.py"

    def test_does_not_flag_log_assertions_the_file_already_had(self):
        before = fixture("python_caplog")
        after = before + "\n\ndef test_settles_twice():\n    assert settle_invoice('inv-2').status == 'settled'\n"
        self.assertEqual(detector.new_hits(self.path, before, after), [])

    def test_does_not_flag_old_assertions_when_their_lines_move(self):
        before = fixture("python_caplog")
        after = "# header\n\n" + before
        self.assertEqual(detector.new_hits(self.path, before, after), [])

    def test_flags_only_the_assertion_added_next_to_an_old_one(self):
        before = fixture("python_caplog")
        added = fixture("python_added_test")
        hits = detector.new_hits(self.path, before, before + added)
        self.assertEqual([(hit.pattern, hit.line) for hit in hits], [("caplog", 14)])

    def test_flags_every_hit_of_a_new_file(self):
        hits = detector.new_hits(self.path, "", fixture("python_caplog"))
        self.assertEqual([hit.line for hit in hits], [9])


class HookProtocolTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(os.path.realpath(self._tmp.name))

    def run_hook(self, payload: dict | None = None, args: list[str] | None = None, env_extra=None):
        env = dict(os.environ, **(env_extra or {}))
        return subprocess.run(
            [str(HOOK), *(args or [])],
            input=json.dumps(payload) if payload is not None else "",
            capture_output=True,
            text=True,
            cwd=self.repo,
            env=env,
            timeout=20,
        )

    def denial(self, result: subprocess.CompletedProcess) -> str | None:
        if not result.stdout.strip():
            return None
        output = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(output["permissionDecision"], "deny")
        return output["permissionDecisionReason"]

    def git(self, *args: str) -> None:
        subprocess.run(
            ["git", "-c", "user.name=fake", "-c", "user.email=fake@example.invalid", *args],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )

    def write_test_file(self, name: str, text: str) -> Path:
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def test_write_denies_a_new_log_assertion_with_rule_location_and_path(self):
        target = self.repo / "tests" / "test_settle.py"
        reason = self.denial(
            self.run_hook({"tool_name": "Write", "tool_input": {"file_path": str(target), "content": fixture("python_caplog")}})
        )
        self.assertIn("Assert the business outcome", reason)
        self.assertIn("design hole", reason)
        self.assertIn(f"{target}:9", reason)
        self.assertIn("claude/rules/test.md", reason)

    def test_edit_denies_only_the_log_assertion_it_adds(self):
        old_file = fixture("python_caplog")
        target = self.write_test_file("tests/test_settle.py", old_file)
        harmless = {"file_path": str(target), "old_string": "settle_invoice(\"inv-1\")", "new_string": "settle_invoice(\"inv-2\")"}
        self.assertIsNone(self.denial(self.run_hook({"tool_name": "Edit", "tool_input": harmless})))

        added = {
            "file_path": str(target),
            "old_string": "caplog.set_level(logging.INFO)\n",
            "new_string": "caplog.set_level(logging.INFO)\n" + fixture("python_inserted_assertion"),
        }
        reason = self.denial(self.run_hook({"tool_name": "Edit", "tool_input": added}))
        self.assertIn(f"{target}:8", reason)
        self.assertNotIn(f"{target}:10", reason)

    def test_multiedit_denies_a_log_assertion_added_by_a_later_edit(self):
        target = self.write_test_file("src/settle.test.ts", fixture("typescript_silenced_console"))
        edits = [
            {"old_string": "expect(settleInvoice", "new_string": "const result = (settleInvoice"},
            {"old_string": ".status).toBe(\"settled\");", "new_string": ".status);\n  expect(console.warn).toHaveBeenCalled();"},
        ]
        reason = self.denial(self.run_hook({"tool_name": "MultiEdit", "tool_input": {"file_path": str(target), "edits": edits}}))
        self.assertIn("src/settle.test.ts:6", reason)

    def test_write_allows_a_test_that_already_had_the_assertion(self):
        target = self.write_test_file("tests/test_settle.py", fixture("python_caplog"))
        rewritten = fixture("python_caplog") + "\n\ndef test_other():\n    assert 1 == 1\n"
        result = self.run_hook({"tool_name": "Write", "tool_input": {"file_path": str(target), "content": rewritten}})
        self.assertIsNone(self.denial(result))

    def test_write_ignores_a_file_that_is_not_a_test(self):
        target = self.repo / "billing" / "settle.py"
        result = self.run_hook({"tool_name": "Write", "tool_input": {"file_path": str(target), "content": fixture("python_caplog")}})
        self.assertIsNone(self.denial(result))

    def test_a_test_about_the_logging_itself_is_denied_and_handed_to_the_owner(self):
        redaction_test = fixture("python_caplog").replace("settled inv-1", "card number never reaches the logs")
        target = self.repo / "tests" / "test_redaction.py"
        payload = {"tool_name": "Write", "tool_input": {"file_path": str(target), "content": redaction_test}}
        reason = self.denial(self.run_hook(payload, env_extra={"CLAUDE_SKIP_CONTENT_GUARD": "1", "LOG_ASSERTION_CHECK": "off"}))
        self.assertIn("subject of this test is the logging itself", reason)
        self.assertIn("tell the owner", reason)
        self.assertNotIn("override", reason.lower())

    def test_commit_denies_a_log_assertion_written_through_the_shell(self):
        self.git("init", "-q")
        self.write_test_file("billing/settle_test.go", fixture("go_buffer"))
        self.git("add", "billing/settle_test.go")
        reason = self.denial(self.run_hook({"tool_name": "Bash", "tool_input": {"command": "git commit -m settle"}}))
        self.assertIn("billing/settle_test.go:17", reason)
        self.assertIn("claude/rules/test.md", reason)
        self.assertIn("commit it by hand", reason)

    def test_commit_allows_a_file_whose_log_assertion_is_already_in_head(self):
        self.git("init", "-q")
        test_file = self.write_test_file("billing/settle_test.go", fixture("go_buffer"))
        self.git("add", ".")
        self.git("commit", "-q", "--no-verify", "-m", "initial")
        test_file.write_text(fixture("go_buffer") + "\nfunc TestOther(t *testing.T) {\n\tif 1 != 1 {\n\t\tt.Fatal()\n\t}\n}\n")
        self.git("add", ".")
        result = self.run_hook({"tool_name": "Bash", "tool_input": {"command": "git commit -m other"}})
        self.assertIsNone(self.denial(result))

    def test_commit_ignores_a_command_that_only_mentions_commit_in_text(self):
        self.git("init", "-q")
        self.write_test_file("billing/settle_test.go", fixture("go_buffer"))
        self.git("add", ".")
        result = self.run_hook({"tool_name": "Bash", "tool_input": {"command": "echo git commit"}})
        self.assertIsNone(self.denial(result))

    def test_cli_exits_one_with_the_rule_for_the_pre_commit_hook(self):
        self.git("init", "-q")
        self.write_test_file("src/settle.test.ts", fixture("typescript_fake_logger"))
        self.git("add", ".")
        result = self.run_hook(args=["--staged"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("src/settle.test.ts:6", result.stderr)
        self.assertIn("--no-verify", result.stderr)

    def test_cli_exits_zero_when_nothing_new_is_staged(self):
        self.git("init", "-q")
        self.write_test_file("README.md", "# nothing\n")
        self.git("add", ".")
        self.assertEqual(self.run_hook(args=["--staged"]).returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run([str(HOOK)], input="not json", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
