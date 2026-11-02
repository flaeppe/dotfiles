"""Tests for statusline-command.sh and subagent-statusline.sh.

Each script runs as a subprocess with logging wrappers for the usual text
tools first on PATH, so the test fails when a script starts more processes
than it does now. Only the wrapped names are seen.

    python3 -m unittest test_statusline -v
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
STATUSLINE = HERE / "statusline-command.sh"
SUBAGENT_STATUSLINE = HERE / "subagent-statusline.sh"

WRAPPED_TOOLS = (
    "jq",
    "awk",
    "cat",
    "sed",
    "grep",
    "tr",
    "cut",
    "date",
    "head",
    "tail",
    "expr",
    "bc",
    "python3",
)

# The one process each script is allowed to start besides bash itself.
ALLOWED_EXECS = ["jq"]

HOME = "/home/owner"


def statusline_payload(**fields) -> str:
    payload = {
        "model": {"display_name": "Opus"},
        "workspace": {"current_dir": HOME + "/project"},
        "context_window": {"total_input_tokens": 123456, "used_percentage": 12.3},
    }
    payload.update(fields)
    return json.dumps(payload)


class StatuslineTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.shim_dir = Path(tmp.name)
        self.exec_log = self.shim_dir / "execs.log"
        self.exec_log.touch()
        for name in WRAPPED_TOOLS:
            real = shutil.which(name)
            if real is None:
                continue
            wrapper = self.shim_dir / name
            wrapper.write_text(
                f'#!/bin/sh\necho {name} >> "{self.exec_log}"\nexec "{real}" "$@"\n'
            )
            wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR)

    def run_script(self, script: Path, payload: str) -> tuple[str, list[str]]:
        env = dict(os.environ, PATH=f"{self.shim_dir}:{os.environ['PATH']}", HOME=HOME)
        result = subprocess.run(
            ["bash", str(script)],
            input=payload,
            capture_output=True,
            text=True,
            env=env,
            check=True,
        )
        return result.stdout, self.exec_log.read_text().split()

    def test_statusline_starts_one_process(self):
        cache = {"prompt_cache": {"hit_ratio": 0.5, "warm": False, "misses": 2}}
        _, execs = self.run_script(STATUSLINE, statusline_payload(**cache))
        self.assertEqual(execs, ALLOWED_EXECS)

    def test_subagent_statusline_starts_one_process_for_all_tasks(self):
        tasks = [
            {"id": f"t{number}", "name": "agent", "tokenCount": 10}
            for number in range(5)
        ]
        _, execs = self.run_script(SUBAGENT_STATUSLINE, json.dumps({"tasks": tasks}))
        self.assertEqual(execs, ALLOWED_EXECS)

    def test_line_with_everything(self):
        cache = {"prompt_cache": {"hit_ratio": 0.9, "warm": True, "misses": 0}}
        line, _ = self.run_script(STATUSLINE, statusline_payload(**cache))
        self.assertEqual(line, "Opus | ~/project | 123k(12%) | cache 90%")

    def test_cold_cache_with_misses(self):
        cache = {"prompt_cache": {"hit_ratio": 0.12, "warm": False, "misses": 3}}
        line, _ = self.run_script(STATUSLINE, statusline_payload(**cache))
        self.assertEqual(line, "Opus | ~/project | 123k(12%) | cache 12% cold !3")

    def test_millions_and_a_directory_outside_home(self):
        payload = statusline_payload(
            workspace={"current_dir": "/tmp/x"},
            context_window={"total_input_tokens": 1234567, "used_percentage": 61.5},
        )
        line, _ = self.run_script(STATUSLINE, payload)
        self.assertEqual(line, "Opus | /tmp/x | 1.2m(62%)")

    def test_empty_payload(self):
        line, _ = self.run_script(STATUSLINE, "{}")
        self.assertEqual(line, "unknown | 0")

    def test_subagent_lines(self):
        tasks = [
            {
                "id": "a1",
                "name": "explore",
                "model": "haiku",
                "effort": "low",
                "tokenCount": 1500,
                "contextWindowSize": 200000,
            },
            {"id": "b2", "label": "build", "tokenCount": 800},
        ]
        output, _ = self.run_script(SUBAGENT_STATUSLINE, json.dumps({"tasks": tasks}))
        self.assertEqual(
            [json.loads(line) for line in output.splitlines()],
            [
                {"id": "a1", "content": "explore · haiku · low · 1% (2k)"},
                {"id": "b2", "content": "build · resolving… · - · 800"},
            ],
        )


if __name__ == "__main__":
    unittest.main()
