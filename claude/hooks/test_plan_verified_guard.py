"""Tests for plan-verified-guard.

Runs the guard as a subprocess against a scratch $HOME, so `~/.plan` inside the
guard resolves into a throwaway tree.

    python3 -m unittest test_plan_verified_guard -v
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "plan-verified-guard"

STALE_PLAN = """---
status: In Progress
verified: 2020-01-01
---
# test

- [ ] step
"""

STALE_PLAN_WITH_REVIEW = """---
status: In Progress
review: status known-wrong, not fixing now
verified: 2020-01-01
---
# test

- [ ] step
"""

NO_FRONTMATTER = "# engine notes\n\n- [ ] step\n"


class PlanVerifiedGuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # Resolved: the guard compares a realpath'd tool_input path against PLAN_ROOT.
        self.home = Path(os.path.realpath(self._tmp.name))
        self.plan_root = self.home / ".plan"
        self.addCleanup(self._tmp.cleanup)

    def tick_checkbox(self, rel_path, content):
        """Run the guard on a body-only Edit of a file holding `content`."""
        target = self.plan_root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        env = dict(os.environ, HOME=str(self.home))
        payload = json.dumps(
            {
                "tool_name": "Edit",
                "tool_input": {
                    "file_path": str(target),
                    "old_string": "- [ ] step",
                    "new_string": "- [x] step",
                },
            }
        )
        return subprocess.run(
            [sys.executable, str(GUARD)], input=payload, capture_output=True, text=True, env=env, timeout=10
        )

    def test_refuses_a_body_edit_of_a_plan_not_restamped_today(self):
        result = self.tick_checkbox("proj/001-plan.md", STALE_PLAN)
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not restamp `verified:`", result.stderr)

    def test_allows_a_body_edit_of_a_plan_carrying_review(self):
        result = self.tick_checkbox("proj/001-plan.md", STALE_PLAN_WITH_REVIEW)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_an_edit_under_the_search_engine_directory(self):
        result = self.tick_checkbox(".index/CLAUDE.md", NO_FRONTMATTER)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_an_edit_under_private(self):
        result = self.tick_checkbox("_private/sweep.md", NO_FRONTMATTER)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
