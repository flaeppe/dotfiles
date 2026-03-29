---
name: commit
description: Use when creating git commits - emphasizes context and intent over diff summaries
---

## Commit Message Guidelines

Use these guidelines when creating git commits.

### Core Principle: Context Over Diff

The commit message should be derived from **session context**—what was planned, discussed, and why the change was made. The diff is for verification only, not the primary source for the message.

If session context is unclear or insufficient, **ask for clarification** before committing.

### Why, Not What

The diff already shows what changed. The message must explain **why**:
- What problem does this solve?
- What was the motivation or intent?
- What decision led to this approach?

### Anti-Patterns (Never Do This)

These read like diff summaries—avoid them:
- "Add X function that does Y"
- "Update Z to handle W"
- "Change A from B to C"
- "Remove unused imports"
- "Fix typo in variable name"

If your message could be auto-generated from the diff, rewrite it.

### Format: Conventional Commits

Structure:
```
type(scope): subject

body
```

**Subject line**:
- Imperative mood ("add" not "added")
- Max 50 characters
- No period at end
- Capitalize first letter after colon

**Types**: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

**Body**:
- Wrap at 72 characters
- Explain motivation and context
- Use bullet points for multiple points
- Blank line between subject and body

### Quick Reference

| Type | Use for |
|------|---------|
| feat | New user-visible behavior |
| fix | Bug fixes |
| docs | Documentation-only changes |
| style | Non-functional formatting |
| refactor | Internal changes without behavior change |
| perf | Performance improvements |
| test | Adding or adjusting tests |
| build | Build system/tooling changes |
| ci | CI configuration changes |
| chore | Maintenance tasks |
| revert | Revert a previous commit |

### Process

1. Recall session context—what was the goal? why this approach?
2. Review staged diff to verify scope
3. If context is unclear, ask the user
4. Write message from context, not from diff
