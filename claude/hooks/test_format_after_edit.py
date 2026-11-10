"""Tests for format-after-edit.

Runs the hook as a subprocess with a stub `ruff` in a project-local .venv that
logs its argv, so the test needs no real ruff.

    python3 -m unittest test_format_after_edit -v
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).parent / "format-after-edit"

STUB = """#!/bin/sh
echo "$@" >> "$(dirname "$0")/argv.log"
"""


class FormatAfterEditTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.project = Path(os.path.realpath(self._tmp.name))
        self.addCleanup(self._tmp.cleanup)
        bin_dir = self.project / ".venv" / "bin"
        bin_dir.mkdir(parents=True)
        stub = bin_dir / "ruff"
        stub.write_text(STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
        self.argv_log = bin_dir / "argv.log"

    def run_hook(self, file_name):
        target = self.project / file_name
        target.write_text("import os\n")
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(target)}})
        return subprocess.run(
            [sys.executable, str(HOOK)], input=payload, capture_output=True, text=True, timeout=10
        )

    def test_check_step_leaves_unused_imports_unfixed(self):
        self.run_hook("a.py")
        check_line = self.argv_log.read_text().splitlines()[0]
        self.assertIn("--unfixable F401", check_line)

    def test_runs_format_after_check(self):
        self.run_hook("a.py")
        lines = self.argv_log.read_text().splitlines()
        self.assertEqual([line.split()[0] for line in lines], ["check", "format"])

    def test_ignores_a_non_python_file(self):
        self.run_hook("a.txt")
        self.assertFalse(self.argv_log.exists())


if __name__ == "__main__":
    unittest.main()
