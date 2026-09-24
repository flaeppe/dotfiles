"""Tests for toolchain-path-guard.

Runs the guard as a subprocess, exactly as Claude Code's PreToolUse hook
would invoke it, with a controlled PATH so results do not depend on what
happens to be installed on the machine running the tests.

    python3 -m unittest test_toolchain_path_guard -v
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).parent / "toolchain-path-guard"

# A real git plus coreutils, no yarn/bun/npx/pnpm/node anywhere on it.
NO_TOOLCHAIN_PATH = "/usr/bin:/bin"


class ToolchainPathGuardTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # Resolved once: macOS puts TemporaryDirectory under a symlink
        # (/var -> /private/var), and the guard walks the real directory
        # chain looking for .envrc.
        self.root = Path(os.path.realpath(self._tmp.name))
        self.addCleanup(self._tmp.cleanup)

    def run_guard(self, command, cwd, path=NO_TOOLCHAIN_PATH):
        env = dict(os.environ)
        env["PATH"] = path
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)})
        return subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, env=env, timeout=10
        )

    def fake_bin(self, name):
        """A directory on PATH containing an executable stub named `name`."""
        bin_dir = self.root / "fakebin"
        bin_dir.mkdir(exist_ok=True)
        stub = bin_dir / name
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        return bin_dir

    def init_repo(self, hooks_path=None, hook_script=None):
        repo = self.root / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        if hooks_path is not None:
            subprocess.run(["git", "config", "core.hooksPath", hooks_path], cwd=repo, check=True)
            hook_dir = repo / hooks_path
        else:
            hook_dir = repo / ".git" / "hooks"
        if hook_script is not None:
            hook_dir.mkdir(parents=True, exist_ok=True)
            name, body = hook_script
            script = hook_dir / name
            script.write_text(body)
            script.chmod(script.stat().st_mode | stat.S_IEXEC)
        return repo

    def test_refuses_yarn_test_outside_path_under_envrc(self):
        (self.root / ".envrc").write_text("use flake\n")
        result = self.run_guard("yarn test", self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("yarn is not on PATH outside direnv here", result.stderr)
        self.assertIn("direnv exec . yarn test", result.stderr)

    def test_allows_when_already_wrapped_in_direnv_exec(self):
        (self.root / ".envrc").write_text("use flake\n")
        result = self.run_guard("direnv exec . yarn test", self.root)
        self.assertEqual(result.returncode, 0)

    def test_allows_when_no_envrc(self):
        result = self.run_guard("yarn test", self.root)
        self.assertEqual(result.returncode, 0)

    def test_allows_when_program_is_on_path(self):
        (self.root / ".envrc").write_text("use flake\n")
        bin_dir = self.fake_bin("yarn")
        result = self.run_guard("yarn test", self.root, path=f"{bin_dir}:{NO_TOOLCHAIN_PATH}")
        self.assertEqual(result.returncode, 0)

    def test_refuses_git_dash_c_push_into_a_husky_repo(self):
        repo = self.init_repo(hooks_path=".husky", hook_script=("pre-push", "#!/bin/sh\nyarn test\n"))
        (repo / ".envrc").write_text("use flake\n")
        result = self.run_guard(f"git -C {repo} push", self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("yarn is not on PATH outside direnv here", result.stderr)
        self.assertIn(f"direnv exec {repo} git -C {repo} push", result.stderr)

    def test_allows_a_plain_git_commit_in_a_repo_with_no_hooks(self):
        repo = self.init_repo()
        (repo / ".envrc").write_text("use flake\n")
        result = self.run_guard('git commit -m "message"', repo)
        self.assertEqual(result.returncode, 0)

    def test_ignores_a_non_bash_tool(self):
        env = dict(os.environ)
        env["PATH"] = NO_TOOLCHAIN_PATH
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "x"}})
        result = subprocess.run(
            [str(GUARD)], input=payload, capture_output=True, text=True, env=env, timeout=10
        )
        self.assertEqual(result.returncode, 0)

    def test_fails_open_on_malformed_stdin(self):
        env = dict(os.environ)
        env["PATH"] = NO_TOOLCHAIN_PATH
        result = subprocess.run(
            [str(GUARD)], input="not json", capture_output=True, text=True, env=env, timeout=10
        )
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
