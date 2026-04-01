---
description: Planning agent - uses Claude Opus 4.6 via Anthropic for superior reasoning and strategic thinking
mode: primary
model: anthropic/claude-opus-4-6
temperature: 0.05
permission:
  edit: ask
  bash:
    "*": ask

    # Git read-only
    "git status": allow
    "git status *": allow
    "git diff": allow
    "git diff *": allow
    "git log": allow
    "git log *": allow
    "git show": allow
    "git show *": allow
    "git branch": allow
    "git branch *": allow
    "git rev-parse *": allow
    "git remote -v": allow
    "git tag": allow
    "git tag *": allow
    "git stash list": allow
    "git stash list *": allow

    # GitHub CLI read-only
    "gh browse *": allow
    "gh issue list *": allow
    "gh issue view *": allow
    "gh issue status *": allow
    "gh pr list *": allow
    "gh pr view *": allow
    "gh pr status *": allow
    "gh pr diff *": allow
    "gh pr checks *": allow
    "gh release list *": allow
    "gh release view *": allow
    "gh repo view *": allow
    "gh repo list *": allow
    "gh search *": allow
    "gh run list *": allow
    "gh run view *": allow
    "gh label list *": allow

    # Filesystem read-only
    "ls": allow
    "ls *": allow
    "cat *": allow
    "head *": allow
    "tail *": allow
    "wc *": allow
    "file *": allow
    "stat *": allow
    "which *": allow
    "type *": allow
    "realpath *": allow
    "readlink *": allow

    # Search
    "rg *": allow
    "fd *": allow
    "find *": allow
    "tree *": allow

    # Environment inspection
    "direnv status": allow
    "direnv status *": allow

    # Build/toolchain inspection
    "nix flake show *": allow
    "nix flake metadata *": allow
    "node --version": allow
    "python --version": allow
    "python3 --version": allow
    "npm list *": allow
    "pip list *": allow
    "pip show *": allow

    # Process/system read-only
    "ps *": allow
    "whoami": allow
    "hostname": allow
    "uname *": allow
    "date": allow
    "date *": allow
    "pwd": allow
---
