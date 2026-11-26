"""Run `review post` against a throwaway review worktree and a stub `gh` on PATH."""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

FUNCTIONS = Path(__file__).resolve().parents[1] / "functions"
PULL_REQUEST = "7"
GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
}

# `gh pr view` reports the PR's tip; `gh api` records the posted payload.
STUB_GH = """#!/bin/sh
if [ "$1" = pr ]; then
    echo "$STUB_PR_TIP OPEN"
    exit 0
fi
cat > "$STUB_PAYLOAD_FILE"
echo "https://github.com/o/r/pull/7#pullrequestreview-1"
"""

# The nix module wraps each file in `function <name> ... end`; sourcing a file with its
# arguments is the same thing without nix.
PRELUDE = f"""
for file in {FUNCTIONS}/_*.fish
    set -l name (basename $file .fish)
    eval "function $name; source $file \\$argv; end"
end
"""


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


class ReviewPostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.payload_file = self.base / "payload.json"
        self.make_pull_request()

    def make_pull_request(self):
        """A review worktree at `reviewed`; `tip` is a later commit of the same repository.

        `reviewed` adds a line to both files; `tip` rewrites only b.txt.
        """
        self.root = self.base / "work"
        self.root.mkdir()
        git(self.root, "init", "-q", "-b", "master")
        for name in ("a.txt", "b.txt"):
            (self.root / name).write_text("one\ntwo\nthree\n")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "base")
        self.merge_base = git(self.root, "rev-parse", "HEAD")

        self.review_tree = self.root / ".worktrees" / "review" / PULL_REQUEST / "head"
        git(self.root, "worktree", "add", "-q", "-b", "pr", str(self.review_tree))
        for name in ("a.txt", "b.txt"):
            (self.review_tree / name).write_text("one\ntwo\nthree\nreviewed\n")
        git(self.review_tree, "commit", "-q", "-am", "reviewed")
        self.reviewed = git(self.review_tree, "rev-parse", "HEAD")

        (self.review_tree / "b.txt").write_text("one\nrewritten\nthree\nreviewed\n")
        git(self.review_tree, "commit", "-q", "-am", "tip")
        self.tip = git(self.review_tree, "rev-parse", "HEAD")
        git(self.review_tree, "reset", "-q", "--hard", self.reviewed)

        git(self.review_tree, "remote", "add", "origin", "git@github.com:o/r.git")

        stub_bin = self.base / "bin"
        stub_bin.mkdir()
        gh = stub_bin / "gh"
        gh.write_text(STUB_GH)
        gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
        self.stub_bin = stub_bin

        review_dir = self.review_tree / ".review"
        review_dir.mkdir()
        (review_dir / "session.json").write_text(
            json.dumps({"merge_base": self.merge_base})
        )
        self.post_json = review_dir / "post.json"

    def write_post_json(self, **extra):
        self.post_json.write_text(
            json.dumps(
                {
                    "event": "APPROVE",
                    "body": "Approve.",
                    "comments": [
                        {"path": "a.txt", "line": 4, "side": "RIGHT", "body": "on a"},
                        {"path": "b.txt", "line": 4, "side": "RIGHT", "body": "on b"},
                    ],
                    **extra,
                }
            )
        )

    def review_post(self, *flags, tip=None):
        env = {
            **os.environ,
            **GIT_ENV,
            "PATH": f"{self.stub_bin}:{os.environ['PATH']}",
            # The function's `git fetch origin` must fail at once, not reach GitHub; the
            # tip is already in the shared object store.
            "GIT_SSH_COMMAND": "false",
            "STUB_PR_TIP": tip or self.tip,
            "STUB_PAYLOAD_FILE": str(self.payload_file),
        }
        script = f"{PRELUDE}\n_review_post {PULL_REQUEST} {' '.join(flags)} 2>&1"
        return subprocess.run(
            ["fish", "--no-config", "-c", script],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_rechecked_review_posts_on_the_tip(self):
        self.write_post_json(rechecked_head=self.tip)
        result = self.review_post()
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(self.payload_file.read_text())
        self.assertEqual(payload["commit_id"], self.tip)

    def test_comment_on_a_file_the_tip_changed_moves_into_the_body(self):
        self.write_post_json(rechecked_head=self.tip)
        result = self.review_post()
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(self.payload_file.read_text())
        self.assertEqual([comment["path"] for comment in payload["comments"]], ["a.txt"])
        self.assertIn("`b.txt:4` — on b", payload["body"])

    def test_unmoved_head_posts_on_the_reviewed_commit(self):
        self.write_post_json()
        result = self.review_post(tip=self.reviewed)
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(self.payload_file.read_text())
        self.assertEqual(payload["commit_id"], self.reviewed)
        self.assertEqual(len(payload["comments"]), 2)

    def test_moved_head_without_recheck_posts_nothing(self):
        self.write_post_json()
        result = self.review_post()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.payload_file.exists())

    def test_dry_run_names_the_commit_it_would_post_on(self):
        self.write_post_json(rechecked_head=self.tip)
        result = self.review_post("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"at {self.tip[:7]}", result.stdout)
        self.assertFalse(self.payload_file.exists())


if __name__ == "__main__":
    unittest.main()
