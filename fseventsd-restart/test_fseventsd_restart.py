"""Run fseventsd-restart.sh against a stubbed footprint and a recording killall."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "fseventsd-restart.sh"
THRESHOLD_BYTES = 8 * 1024**3


class FseventsdRestartTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.log = Path(tmp.name) / "restart.log"
        self.killall_calls = Path(tmp.name) / "killall.calls"
        killall = Path(tmp.name) / "killall"
        killall.write_text(f'#!/bin/sh\necho "$@" >> {self.killall_calls}\n')
        killall.chmod(0o755)
        self.killall = killall

    def run_script(self, *args, footprint_bytes=None):
        env = {
            **os.environ,
            "FSEVENTSD_KILLALL": str(self.killall),
            "FSEVENTSD_RESTART_LOG": str(self.log),
        }
        env.pop("FSEVENTSD_FOOTPRINT_BYTES", None)
        if footprint_bytes is not None:
            env["FSEVENTSD_FOOTPRINT_BYTES"] = str(footprint_bytes)
        return subprocess.run(
            ["/bin/sh", str(SCRIPT), *args], env=env, capture_output=True, text=True
        )

    def test_dry_run_over_threshold_prints_the_restart(self):
        result = self.run_script("--dry-run", footprint_bytes=THRESHOLD_BYTES + 1)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("would restart:", result.stdout)
        self.assertFalse(self.killall_calls.exists())
        self.assertFalse(self.log.exists())

    def test_over_threshold_restarts_and_logs_one_line(self):
        footprint_bytes = THRESHOLD_BYTES + 1
        result = self.run_script(footprint_bytes=footprint_bytes)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.killall_calls.read_text().strip(), "fseventsd")
        lines = self.log.read_text().splitlines()
        self.assertEqual(len(lines), 1)
        timestamp = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"
        self.assertRegex(
            lines[0], rf"^{timestamp} restart footprint_bytes={footprint_bytes} "
        )

    def test_at_threshold_does_not_restart(self):
        result = self.run_script(footprint_bytes=THRESHOLD_BYTES)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no restart:", result.stdout)
        self.assertFalse(self.killall_calls.exists())
        self.assertFalse(self.log.exists())

    def test_unknown_argument_is_refused(self):
        result = self.run_script("--now", footprint_bytes=THRESHOLD_BYTES + 1)

        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.killall_calls.exists())

    def test_reads_the_live_footprint(self):
        result = self.run_script("--dry-run")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"footprint_bytes=[1-9]\d+ ")
        self.assertFalse(self.killall_calls.exists())


if __name__ == "__main__":
    unittest.main()
