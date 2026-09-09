## Codex conventions

- Never add tool attribution, generated-by notices, or AI co-author trailers to
  commit messages or pull request bodies.
- Preserve the requested model. Do not select another model to work around a
  limit or availability error without the user's instruction.
- Before working below the launch directory, find and read applicable nested
  `AGENTS.override.md`, `AGENTS.md`, or `CLAUDE.md` files along the target path.
  Use the first available name in that order per directory. Codex does not
  automatically load this guidance when a shell command reads a child file.
- Use the `coding-conventions` skill for implementation and tests. Its references
  share the language and test conventions used by the other coding agent.
