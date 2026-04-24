---
description: Reviews code for security, performance, and maintainability - uses Claude Opus 4.6 for deep analysis
mode: subagent
model: anthropic/claude-opus-4-6
temperature: 0.05
permission:
  edit: deny
  bash:
    "git diff": allow
    "git log*": allow
    "*": ask
---

## Available MCP Tools

Use these when relevant:

- `codebase-memory-mcp` — Query the code knowledge graph for call chains, dependencies, callers, and structural analysis
- `github-work` — Read PR details, review comments, check runs, and issue context (read-only token)
