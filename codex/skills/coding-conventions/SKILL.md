---
name: coding-conventions
description: Apply personal language and test conventions when implementing, editing, or reviewing Python, TypeScript, Go, or Nix code and tests. Skip for prose-only tasks.
---

Read the relevant files in `references/` before editing or reviewing code:

- Python: `python.md`; pytest tests also use `test.md` and `pytest.md`.
- TypeScript: `typescript.md`; tests also use `test.md` and the matching
  `jest.md` or `vitest.md`, determined from the repository's dependencies.
- Go: `golang.md`; tests also use `test.md` and `golang-test.md`.
- Nix: `nix.md`.

Read only the applicable references. Their `paths:` frontmatter describes the
intended scope; it does not automatically activate rules in Codex. Apply nested
repository instructions and the user's explicit requirements when they differ.
