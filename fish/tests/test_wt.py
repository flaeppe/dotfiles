"""Run `wt new` and `wt rm` in throwaway repos with an unpushed local default."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

FUNCTIONS = Path(__file__).resolve().parents[1] / "functions"
GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
}


def git(cwd, *args):
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        env={**os.environ, **GIT_ENV},
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


# The nix module wraps each file in `function <name> ... end`; sourcing a file with its
# arguments is the same thing without nix.
PRELUDE = f"""
for file in {FUNCTIONS}/_*.fish
    set -l name (basename $file .fish)
    eval "function $name; source $file \\$argv; end"
end
"""


def fish(cwd, script):
    return subprocess.run(
        ["fish", "--no-config", "-c", f"{PRELUDE}\n{script}"],
        cwd=cwd,
        env={**os.environ, **GIT_ENV},
        capture_output=True,
        text=True,
        check=False,
    )


class WtTestCase(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()

    def make_repo(self, local_ahead, with_origin=True):
        """A clone whose local master is `local_ahead` commits past origin/master."""
        seed = self.base / "seed"
        seed.mkdir()
        git(seed, "init", "-q", "-b", "master")
        git(seed, "commit", "-q", "--allow-empty", "-m", "base")
        if with_origin:
            git(self.base, "clone", "-q", "--bare", "seed", "origin.git")
            git(self.base, "clone", "-q", "origin.git", "work")
            git(self.base / "work", "remote", "set-head", "origin", "-a")
            root = self.base / "work"
        else:
            root = seed
        for number in range(local_ahead):
            git(root, "commit", "-q", "--allow-empty", "-m", f"local {number}")
        self.root = root
        return root

    def commit_in(self, tree, message):
        git(tree, "commit", "-q", "--allow-empty", "-m", message)


class WtNewWarningTests(WtTestCase):
    def test_warning_is_last_and_names_a_remedy_that_starts_from_the_local_commits(
        self,
    ):
        root = self.make_repo(local_ahead=3)
        result = fish(root, "_wt_new x 2>&1")
        lines = result.stdout.splitlines()
        self.assertEqual(result.returncode, 0, result.stdout)
        success = lines.index("wt new: x on x")
        self.assertIn(
            "WARNING local master is 3 commit(s) ahead of origin/master",
            lines[success + 1],
        )
        tip = git(root, "rev-parse", "--short", "master")
        self.assertEqual(
            lines[-1], f"wt new: to start from them, remove it and run: wt new x {tip}"
        )

        remedy = fish(root, f"_wt_new y {tip} 2>&1")
        self.assertEqual(remedy.returncode, 0, remedy.stdout)
        self.assertEqual(
            git(root / ".worktrees" / "y", "rev-parse", "HEAD"),
            git(root, "rev-parse", "master"),
        )

    def test_no_warning_when_local_default_matches_origin(self):
        root = self.make_repo(local_ahead=0)
        result = fish(root, "_wt_new x 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_no_warning_for_an_existing_branch(self):
        root = self.make_repo(local_ahead=3)
        git(root, "branch", "feature", "origin/master")
        result = fish(root, "_wt_new x feature 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_no_warning_for_a_named_sha(self):
        root = self.make_repo(local_ahead=3)
        sha = git(root, "rev-parse", "--short", "origin/master")
        result = fish(root, f"_wt_new x {sha} 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_no_warning_for_a_named_remote_ref(self):
        root = self.make_repo(local_ahead=3)
        result = fish(root, "_wt_new x origin/master 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_new_branch_name_still_warns_because_its_base_is_the_stale_default(self):
        root = self.make_repo(local_ahead=3)
        result = fish(root, "_wt_new x brand-new 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("WARNING local master is 3 commit(s) ahead", result.stdout)

    def test_no_origin_means_no_warning(self):
        root = self.make_repo(local_ahead=3, with_origin=False)
        result = fish(root, "_wt_new x 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("no origin/HEAD, branching off local master", result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_deleted_local_default_means_no_warning(self):
        root = self.make_repo(local_ahead=3)
        git(root, "checkout", "-q", "-b", "side")
        git(root, "branch", "-D", "master")
        result = fish(root, "_wt_new x 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARNING", result.stdout)

    def test_detached_main_checkout_with_origin_still_bases_on_origin(self):
        root = self.make_repo(local_ahead=3)
        git(root, "checkout", "-q", "--detach")
        result = fish(root, "_wt_new x 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("WARNING local master is 3 commit(s) ahead", result.stdout)


class WtRemoveTests(WtTestCase):
    def new_tree(self, name, start=None):
        # `wt new <name> master` is refused while the main checkout holds master, so a
        # ref to start from is passed as the sha it resolves to.
        sha = git(self.root, "rev-parse", "--short", start) if start else ""
        result = fish(self.root, f"_wt_new {name} {sha} 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        return self.root / ".worktrees" / name

    def test_branch_fast_forwarded_into_the_unpushed_default_is_removed_without_force(
        self,
    ):
        root = self.make_repo(local_ahead=3)
        tree = self.new_tree("w", start="master")
        self.commit_in(tree, "work")
        git(root, "merge", "-q", "--ff-only", "w")
        result = fish(root, "_wt_rm w 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(tree.exists())
        self.assertIn("deleted branch w", result.stdout)

    def test_branch_with_a_commit_on_no_other_branch_is_refused(self):
        root = self.make_repo(local_ahead=3)
        tree = self.new_tree("w")
        self.commit_in(tree, "unmerged work")
        result = fish(root, "_wt_rm w 2>&1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("1 commit(s) that were never pushed", result.stdout)
        self.assertTrue(tree.exists())

    def test_refusal_counts_only_the_commits_the_default_lacks(self):
        root = self.make_repo(local_ahead=3)
        tree = self.new_tree("w", start="master")
        self.commit_in(tree, "unmerged work")
        result = fish(root, "_wt_rm w 2>&1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("1 commit(s) that were never pushed", result.stdout)
        self.assertTrue(tree.exists())

    def test_deleted_local_default_still_refuses_unmerged_work(self):
        root = self.make_repo(local_ahead=0)
        tree = self.new_tree("w")
        self.commit_in(tree, "unmerged work")
        git(root, "checkout", "-q", "-b", "side")
        git(root, "branch", "-D", "master")
        result = fish(root, "_wt_rm w 2>&1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertTrue(tree.exists())

    def test_detached_tree_on_a_default_commit_is_removed(self):
        root = self.make_repo(local_ahead=3)
        tree = root / ".worktrees" / "d"
        git(root, "worktree", "add", "-q", "--detach", str(tree), "master")
        result = fish(root, "_wt_rm d 2>&1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(tree.exists())

    def test_detached_tree_holding_unreachable_commits_is_refused(self):
        root = self.make_repo(local_ahead=3)
        tree = root / ".worktrees" / "d"
        git(root, "worktree", "add", "-q", "--detach", str(tree), "master")
        self.commit_in(tree, "unreachable")
        result = fish(root, "_wt_rm d 2>&1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("detached with 1 commit(s) no branch points at", result.stdout)
        self.assertTrue(tree.exists())

    def test_no_origin_merged_branch_is_removed_and_unmerged_is_refused(self):
        root = self.make_repo(local_ahead=1, with_origin=False)
        merged = self.new_tree("merged")
        unmerged = self.new_tree("unmerged")
        self.commit_in(unmerged, "unmerged work")
        result = fish(root, "_wt_rm merged unmerged 2>&1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertFalse(merged.exists())
        self.assertTrue(unmerged.exists())


if __name__ == "__main__":
    unittest.main()
