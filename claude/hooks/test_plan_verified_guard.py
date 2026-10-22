"""Tests for plan-verified-guard.

Runs the guard as a subprocess against a scratch $HOME, so `~/.plan` inside the
guard resolves into a throwaway tree.

    python3 -m unittest test_plan_verified_guard -v
"""

from __future__ import annotations

import datetime as dt
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

TODAY = dt.date.today().isoformat()

FLOW_VERIFIED = "verified: {by: claude-code/unrecorded, at: %s}"
BLOCK_VERIFIED = "verified:\n  by: claude-code/unrecorded\n  at: %s"
LIST_VERIFIED = "verified:\n  - by: claude-code/unrecorded\n    at: 2019-05-05\n  - by: process:restamp\n    at: %s"
VERIFIED_FORMS = {"flow": FLOW_VERIFIED, "block": BLOCK_VERIFIED, "list": LIST_VERIFIED}


def mapped_plan(verified, banner=False):
    body = "> **UNVERIFIED** \u2014 refs moved. Resolve before relying on this file.\n" if banner else ""
    return "---\ntype: Plan\nstatus: draft\nstage: In Progress\n%s\n---\n# test\n\n%s- [ ] step\n" % (verified, body)


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

    def edit(self, rel_path, content, old_string, new_string):
        target = self.plan_root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        env = dict(os.environ, HOME=str(self.home))
        payload = json.dumps(
            {
                "tool_name": "Edit",
                "tool_input": {"file_path": str(target), "old_string": old_string, "new_string": new_string},
            }
        )
        return subprocess.run(
            [sys.executable, str(GUARD)], input=payload, capture_output=True, text=True, env=env, timeout=10
        )

    def test_refuses_a_body_edit_of_a_mapped_plan_stamped_before_today(self):
        for form, template in VERIFIED_FORMS.items():
            with self.subTest(form=form):
                stale = template % "2020-01-01"
                result = self.tick_checkbox("proj/001-plan.md", mapped_plan(stale))
                self.assertEqual(result.returncode, 2)
                self.assertIn("does not restamp `verified:` (currently 2020-01-01", result.stderr)

    def test_allows_a_body_edit_of_a_mapped_plan_stamped_today(self):
        for form, template in VERIFIED_FORMS.items():
            with self.subTest(form=form):
                result = self.tick_checkbox("proj/001-plan.md", mapped_plan(template % TODAY))
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_list_is_compared_by_its_latest_at(self):
        result = self.tick_checkbox("proj/001-plan.md", mapped_plan(LIST_VERIFIED % "2020-01-01"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("currently 2020-01-01", result.stderr)

    def test_allows_an_edit_that_restamps_in_any_form(self):
        old = mapped_plan(FLOW_VERIFIED % "2020-01-01")
        restamps = {
            "plain": ("verified: 2020-01-01", "verified: %s" % TODAY),
            "flow": ("verified: {by: claude-code/unrecorded, at: 2020-01-01}", FLOW_VERIFIED % TODAY),
            "block-at-line": (BLOCK_VERIFIED % "2020-01-01", BLOCK_VERIFIED % TODAY),
            "at-line-only": ("  at: 2020-01-01", "  at: %s" % TODAY),
        }
        for form, (old_string, new_string) in restamps.items():
            with self.subTest(form=form):
                content = old.replace(FLOW_VERIFIED % "2020-01-01", old_string)
                result = self.edit("proj/001-plan.md", content, old_string, new_string)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_refuses_a_restamp_of_a_mapped_plan_whose_banner_stays(self):
        stale = mapped_plan(FLOW_VERIFIED % "2020-01-01", banner=True)
        result = self.edit("proj/001-plan.md", stale, "verified: {by: claude-code/unrecorded, at: 2020-01-01}", FLOW_VERIFIED % TODAY)
        self.assertEqual(result.returncode, 2)
        self.assertIn("taint banner", result.stderr)

    def test_refuses_a_body_edit_of__a_plan_not_restamped_today(self):
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
