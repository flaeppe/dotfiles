---
description: Senior dependency-graph expert — coupling, boundaries, awareness, abstraction quality at every layer
mode: subagent
model: anthropic/claude-opus-4-6
temperature: 0.1
permission:
  edit: deny
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

    # Filesystem read-only
    "ls": allow
    "ls *": allow
    "cat *": allow
    "head *": allow
    "tail *": allow
    "wc *": allow
    "file *": allow
    "stat *": allow
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
    "pwd": allow
---
