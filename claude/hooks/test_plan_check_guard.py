"""Tests for plan-check-guard.

Runs the guard as a subprocess, exactly as Claude Code's PreToolUse hook
would invoke it, against a scratch $HOME -- so `os.path.expanduser("~/.plan")`
inside the guard resolves into a throwaway tree instead of the real one.
`me` itself is looked up on PATH (unaffected by the scratch $HOME), so the
guard exercises the real check-file gate.

    python3 -m unittest test_plan_check_guard -v
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "plan-check-guard"

IN_PROGRESS_NO_CHECK = """---
status: draft
stage: In Progress
type: Build
date: 2026-09-11
---
# test

## Done when
- [ ] something
"""

IN_PROGRESS_WITH_CHECK = """---
status: draft
stage: In Progress
type: Build
date: 2026-09-11
---
# test

## Done when
- [ ] something (CHECK: true)
"""

DRAFT_NO_CHECK = """---
status: draft
stage: Draft
type: Build
date: 2026-09-11
---
# test
"""

IN_PROGRESS_FENCED_CHECK = """---
status: draft
stage: In Progress
type: Build
date: 2026-09-11
---
# test

## Done when
```
(CHECK: true)
```
"""


IN_PROGRESS_NO_DONE_WHEN = """---
status: draft
stage: In Progress
type: Build
date: 2026-09-11
---
# test

## Notes
- [ ] something (CHECK: true)
"""

JOURNAL_GOAL_WITH_CHECK = """---
status: draft
stage: In Progress
type: Decision
date: 2026-09-11
---
# test

## Journal goal
End state.
- [ ] something (step 1; CHECK: Checks t1)
"""

JOURNAL_GOAL_PROSE_ONLY = """---
status: draft
stage: In Progress
type: Decision
date: 2026-09-11
---
# test

## Journal goal
End state.
- [ ] something with no marker
"""

JOURNAL_GOAL_AND_EMPTY_DONE_WHEN = JOURNAL_GOAL_WITH_CHECK + """
## Done when
- [ ] something with no marker
"""

JOURNAL_GOAL_FENCED_CHECK = """---
status: draft
stage: In Progress
type: Decision
date: 2026-09-11
---
# test

## Journal goal
```
- [ ] something (step 1; CHECK: Checks t1)
```
"""


class PlanCheckGuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # Resolved once here: the guard compares a realpath'd tool_input path
        # against an unresolved PLAN_ROOT, same as plan-verified-guard. On
        # macOS /var/folders is itself a symlink to /private/var/folders, so
        # an unresolved scratch $HOME would never match its own realpath'd
        # children -- resolve it up front so the two sides agree, exactly as
        # they do for the real, non-symlinked $HOME this guard runs under.
        self.home = Path(os.path.realpath(self._tmp.name))
        self.plan_root = self.home / ".plan"
        self.plan_root.mkdir()
        (self.plan_root / "_private").mkdir()
        (self.plan_root / "somerepo" / "reasoning").mkdir(parents=True)
        self.addCleanup(self._tmp.cleanup)

    def run_guard(self, tool_name, tool_input, env_overrides=None):
        env = dict(os.environ)
        env["HOME"] = str(self.home)
        if env_overrides:
            env.update(env_overrides)
        payload = json.dumps({"tool_name": tool_name, "tool_input": tool_input})
        return subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, env=env, timeout=10
        )

    def write_result(self, rel_path, content, tool_name="Write"):
        target = self.plan_root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        return self.run_guard(tool_name, {"file_path": str(target), "content": content})

    def test_denies_in_progress_with_no_check(self):
        result = self.write_result("foo/001-plan.md", IN_PROGRESS_NO_CHECK)
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stderr)
        self.assertNotIn("code fence", result.stderr)

    def test_denies_a_fenced_check_with_a_message_naming_the_fence(self):
        result = self.write_result("foo/007-plan.md", IN_PROGRESS_FENCED_CHECK)
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stderr)
        self.assertIn("inside a code fence", result.stderr)
        self.assertIn("unfence it", result.stderr)

    def test_allows_in_progress_with_a_check(self):
        result = self.write_result("foo/002-plan.md", IN_PROGRESS_WITH_CHECK)
        self.assertEqual(result.returncode, 0)

    def test_allows_draft_with_no_check(self):
        result = self.write_result("foo/003-plan.md", DRAFT_NO_CHECK)
        self.assertEqual(result.returncode, 0)

    def test_allows_private_directory_unconditionally(self):
        result = self.write_result("_private/scratch.md", IN_PROGRESS_NO_CHECK)
        self.assertEqual(result.returncode, 0)

    def test_allows_an_overview_draft_fragment_without_frontmatter(self):
        result = self.write_result("proj/018-overview-draft/part.md", "## Impact\nnone\n")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_reasoning_directory_unconditionally(self):
        result = self.write_result("somerepo/reasoning/note.md", IN_PROGRESS_NO_CHECK)
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        env = dict(os.environ)
        env["HOME"] = str(self.home)
        result = subprocess.run(
            [str(GUARD)], input="not json", capture_output=True, text=True, env=env, timeout=10
        )
        self.assertEqual(result.returncode, 0)

    def test_fails_open_when_me_binary_is_unavailable(self):
        target = self.plan_root / "foo" / "004-plan.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        # Strip only the directory `me` actually lives in from PATH -- an
        # empty PATH also breaks /usr/bin/python3 itself on this machine (its
        # shebang is a stub that needs PATH to find the real interpreter),
        # which would fail the test for the wrong reason.
        import shutil as _shutil

        me_dir = os.path.dirname(_shutil.which("me") or "")
        pruned_path = os.pathsep.join(
            part for part in os.environ.get("PATH", "").split(os.pathsep) if part != me_dir
        )
        result = self.run_guard(
            "Write",
            {"file_path": str(target), "content": IN_PROGRESS_NO_CHECK},
            env_overrides={"PATH": pruned_path},
        )
        self.assertEqual(result.returncode, 0)

    def test_ignores_a_non_plan_tool(self):
        result = self.run_guard("Bash", {"command": "echo hi"})
        self.assertEqual(result.returncode, 0)

    def test_edit_reconstructs_content_before_gating(self):
        target = self.plan_root / "foo" / "006-plan.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(DRAFT_NO_CHECK)
        result = self.run_guard(
            "Edit",
            {
                "file_path": str(target),
                "old_string": "stage: Draft",
                "new_string": "stage: In Progress",
            },
        )
        self.assertEqual(result.returncode, 2)

        target.write_text(DRAFT_NO_CHECK.replace("# test", "# test\n\n## Done when\n- x (CHECK: true)"))
        result = self.run_guard(
            "Edit",
            {
                "file_path": str(target),
                "old_string": "stage: Draft",
                "new_string": "stage: In Progress",
            },
        )
        self.assertEqual(result.returncode, 0)

    def test_denies_a_plan_with_neither_done_when_nor_journal_goal(self):
        result = self.write_result("foo/008-plan.md", IN_PROGRESS_NO_DONE_WHEN)
        self.assertEqual(result.returncode, 2)
        self.assertIn('no "## Done when" heading', result.stderr)

    def test_allows_an_edit_to_a_goal_whose_journal_goal_holds_check_ticks(self):
        target = self.plan_root / "foo" / "001-goal.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(JOURNAL_GOAL_WITH_CHECK)
        result = self.run_guard(
            "Edit",
            {"file_path": str(target), "old_string": "End state.", "new_string": "End state, edited."},
        )
        self.assertEqual(result.returncode, 0)

    def test_denies_a_journal_goal_whose_ticks_carry_no_check(self):
        result = self.write_result("foo/009-goal.md", JOURNAL_GOAL_PROSE_ONLY)
        self.assertEqual(result.returncode, 2)
        self.assertIn('"## Done when" heading', result.stderr)

    def test_denies_an_empty_done_when_even_beside_a_journal_goal(self):
        result = self.write_result("foo/011-goal.md", JOURNAL_GOAL_AND_EMPTY_DONE_WHEN)
        self.assertEqual(result.returncode, 2)
        self.assertIn("carries no (CHECK:", result.stderr)

    def test_denies_a_journal_goal_tick_inside_a_code_fence(self):
        result = self.write_result("foo/010-goal.md", JOURNAL_GOAL_FENCED_CHECK)
        self.assertEqual(result.returncode, 2)
        self.assertIn('"## Done when" heading', result.stderr)


if __name__ == "__main__":
    unittest.main()
