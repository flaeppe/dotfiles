"""Tests for log-assertion-check.

Detection is exercised in-process on fixture snippets (log_assertion_fixtures/,
kept out of *.py so the hook never reads them as tests). The hook protocol is
exercised as a subprocess, exactly as Claude Code's PreToolUse hook would
invoke it, with the state file redirected to a temporary directory.

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

    def test_flags_a_business_test_whatever_its_name_says_about_logging(self):
        for name in (
            "TestClientErrorsAreNotLoggedAtErrorAndServerErrorsAre",
            "TestHandleMessageLogsLevelByReferenceLength",
        ):
            named_test = fixture("go_buffer").replace("TestSettleInvoice", name)
            hits = detector.find_hits("fake-service/handler_test.go", named_test)
            self.assertEqual([hit.line for hit in hits], [17], name)

    def test_ignores_a_test_in_a_logging_package(self):
        for path in (
            "internal/logging/settle_test.go",
            "internal/logger/redact/settle_test.go",
            "pkg/redaction/settle_test.go",
            "internal/log/settle_test.go",
        ):
            self.assertEqual(detector.find_hits(path, fixture("go_buffer")), [], path)

    def test_ignores_a_test_in_a_logger_or_formatter_file(self):
        self.assertEqual(detector.find_hits("tests/test_logging.py", fixture("python_caplog")), [])
        self.assertEqual(detector.find_hits("billing/logger_test.go", fixture("go_buffer")), [])
        self.assertEqual(detector.find_hits("src/json-formatter.test.ts", fixture("typescript_spy_console")), [])

    def test_does_not_mistake_login_or_catalog_for_logging(self):
        self.assertEqual(len(detector.find_hits("tests/login/test_catalog.py", fixture("python_caplog"))), 1)

    def test_a_logging_name_above_the_nearest_directories_does_not_exempt(self):
        path = "/work/logging-platform/billing/api/settle_test.go"
        self.assertEqual(len(detector.find_hits(path, fixture("go_buffer"))), 1)

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

    def test_does_not_flag_an_existing_assertion_whose_text_was_edited(self):
        before = fixture("python_caplog")
        after = before.replace('"settled inv-1"', '"settled invoice inv-1"')
        self.assertEqual(detector.new_hits(self.path, before, after), [])

    def test_flags_every_hit_of_a_new_file(self):
        hits = detector.new_hits(self.path, "", fixture("python_caplog"))
        self.assertEqual([hit.line for hit in hits], [9])


class HookProtocolTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(os.path.realpath(self._tmp.name)) / "ledger"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        self.state = self.repo.parent / "state.jsonl"

    def run_hook(self, args: list[str] | None = None, payload: dict | None = None):
        return subprocess.run(
            [str(HOOK), *(args or [])],
            input=json.dumps(payload) if payload is not None else "",
            capture_output=True,
            text=True,
            cwd=self.repo,
            env=dict(os.environ, LOG_ASSERTION_CHECK_STATE=str(self.state)),
            timeout=20,
        )

    def write_via_hook(self, tool_name: str, tool_input: dict, session: str = "s1"):
        payload = {"tool_name": tool_name, "tool_input": tool_input, "session_id": session}
        result = self.run_hook(payload=payload)
        self.assertEqual(result.returncode, 0)
        if tool_name == "Write":
            self.write_test_file(os.path.relpath(tool_input["file_path"], self.repo), tool_input["content"])
        return result

    def refusal(self, result: subprocess.CompletedProcess) -> str | None:
        if not result.stdout.strip():
            return None
        output = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(output["permissionDecision"], "deny")
        return output["permissionDecisionReason"]

    def records(self) -> list[dict]:
        if not self.state.exists():
            return []
        return [json.loads(line) for line in self.state.read_text().splitlines()]

    def write_test_file(self, name: str, text: str) -> Path:
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def test_write_is_refused_for_a_new_log_assertion(self):
        target = self.repo / "tests" / "test_settle.py"
        result = self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog")})
        message = self.refusal(result)
        self.assertIn("Assert the business outcome", message)
        self.assertIn("design hole", message)
        self.assertIn(f"{target}:9", message)
        self.assertIn("claude/rules/test.md", message)
        self.assertIn("not exempt", message)

    def test_write_is_refused_for_both_log_level_tests_that_slipped_through(self):
        for name in (
            "TestClientErrorsAreNotLoggedAtErrorAndServerErrorsAre",
            "TestHandleMessageLogsLevelByReferenceLength",
        ):
            target = self.repo / "handler" / "handler_test.go"
            content = fixture("go_buffer").replace("TestSettleInvoice", name)
            message = self.refusal(self.write_via_hook("Write", {"file_path": str(target), "content": content}))
            self.assertIn(f"{target}:17", message, name)
            target.unlink()

    def test_write_is_allowed_for_a_test_in_a_logging_package(self):
        target = self.repo / "internal" / "logging" / "redact_test.go"
        result = self.write_via_hook("Write", {"file_path": str(target), "content": fixture("go_buffer")})
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        self.assertEqual(self.records(), [])

    def test_edit_refuses_only_the_log_assertion_it_adds(self):
        target = self.write_test_file("tests/test_settle.py", fixture("python_caplog"))
        harmless = {"file_path": str(target), "old_string": 'settle_invoice("inv-1")', "new_string": 'settle_invoice("inv-2")'}
        self.assertIsNone(self.refusal(self.write_via_hook("Edit", harmless)))

        added = {
            "file_path": str(target),
            "old_string": "caplog.set_level(logging.INFO)\n",
            "new_string": "caplog.set_level(logging.INFO)\n" + fixture("python_inserted_assertion"),
        }
        message = self.refusal(self.write_via_hook("Edit", added))
        self.assertIn(f"{target}:8", message)
        self.assertNotIn(f"{target}:10", message)

    def test_multiedit_refuses_a_log_assertion_added_by_a_later_edit(self):
        target = self.write_test_file("src/settle.test.ts", fixture("typescript_silenced_console"))
        edits = [
            {"old_string": "expect(settleInvoice", "new_string": "const result = (settleInvoice"},
            {"old_string": ".status).toBe(\"settled\");", "new_string": ".status);\n  expect(console.warn).toHaveBeenCalled();"},
        ]
        message = self.refusal(self.write_via_hook("MultiEdit", {"file_path": str(target), "edits": edits}))
        self.assertIn("src/settle.test.ts:6", message)

    def test_write_is_silent_when_the_test_already_had_the_assertion(self):
        target = self.write_test_file("tests/test_settle.py", fixture("python_caplog"))
        rewritten = fixture("python_caplog") + "\n\ndef test_other():\n    assert 1 == 1\n"
        result = self.write_via_hook("Write", {"file_path": str(target), "content": rewritten})
        self.assertIsNone(self.refusal(result))
        self.assertEqual(self.records(), [])

    def test_write_ignores_a_file_that_is_not_a_test(self):
        target = self.repo / "billing" / "settle.py"
        result = self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog")})
        self.assertIsNone(self.refusal(result))
        self.assertEqual(self.records(), [])

    def test_a_fire_is_recorded_with_time_repo_file_line_and_session(self):
        target = self.repo / "tests" / "test_settle.py"
        self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog")}, session="abc")
        (record,) = self.records()
        self.assertEqual(record["event"], "fire")
        self.assertEqual(record["repo"], "ledger")
        self.assertEqual(record["file"], str(target))
        self.assertEqual(record["line"], 'assert "settled inv-1" in caplog.text')
        self.assertEqual(record["session"], "abc")
        self.assertRegex(record["ts"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")

    def test_the_next_write_of_the_file_records_that_the_line_is_still_there(self):
        target = self.repo / "tests" / "test_settle.py"
        flagged = fixture("python_caplog")
        self.write_via_hook("Write", {"file_path": str(target), "content": flagged})
        self.write_via_hook("Write", {"file_path": str(target), "content": flagged + "\n\ndef test_other():\n    assert 1 == 1\n"})

        (fire, followup) = self.records()
        self.assertEqual(followup["fire"], fire["id"])
        self.assertTrue(followup["held"])

    def test_a_removed_line_is_recorded_as_not_held(self):
        target = self.repo / "tests" / "test_settle.py"
        self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog")})
        fixed = fixture("python_caplog").replace('assert "settled inv-1" in caplog.text', "assert settle_invoice('inv-1').status == 'settled'")
        self.write_via_hook("Write", {"file_path": str(target), "content": fixed})

        (fire, followup) = self.records()
        self.assertEqual(followup["fire"], fire["id"])
        self.assertFalse(followup["held"])

    def test_report_counts_writes_lines_and_follow_ups_per_day_and_repo(self):
        target = self.repo / "tests" / "test_settle.py"
        self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog")})
        self.write_via_hook("Write", {"file_path": str(target), "content": fixture("python_caplog") + "\n"})

        lines = self.run_hook(["--report"]).stdout.splitlines()
        self.assertEqual(lines[0].split(), ["day", "repo", "writes", "lines", "followed", "held"])
        self.assertEqual(lines[1].split()[1:], ["ledger", "1", "1", "1", "1"])

    def test_report_says_so_when_nothing_has_fired(self):
        self.assertEqual(self.run_hook(["--report"]).stdout.strip(), "no fires recorded")

    def test_fails_open_on_malformed_stdin(self):
        result = subprocess.run([str(HOOK)], input="not json", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_ignores_a_shell_command(self):
        result = self.run_hook(payload={"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}})
        self.assertEqual((result.returncode, result.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
