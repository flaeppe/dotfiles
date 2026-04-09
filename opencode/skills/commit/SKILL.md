---
name: commit
description: Use when creating git commits
user-invocable: true
---

## Commit Message Guidelines

Use these guidelines when creating git commits.

### Core Principle: Diff-Grounded Intent

The commit message explains **why** the changes in the diff were made. Every claim in the message must be grounded in what the diff actually shows or directly concludable from it.

Session context may inform your understanding of the diff, but must not leak into the message. If a reader with only the diff and the commit message would be confused by a statement, remove it.

If the diff alone is insufficient to understand the intent, **ask for clarification** before committing.

### Why, Not What

The diff already shows what changed. The message must explain **why those specific changes** were made:
- What problem do the changes in the diff solve?
- What was the motivation behind this particular approach?
- What does this change enable or fix, as evidenced by the diff?

The "why" must be answerable from the diff itself—not from alternatives discussed, things not included, or reasoning that only makes sense with conversation history.

### Anti-Patterns (Never Do This)

These read like diff summaries—avoid them:
- "Add X function that does Y"
- "Update Z to handle W"
- "Change A from B to C"
- "Remove unused imports"
- "Fix typo in variable name"

If your message could be auto-generated from the diff, rewrite it.

These leak conversation context—also avoid them:
- "Didn't include X because..." (X isn't in the diff)
- "As discussed, we decided to..."
- "Avoids the approach we considered..."
- Any justification for what was *not* changed

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

1. Review the staged diff—what changed, and why does the code show that intent?
2. If the diff alone doesn't make the intent clear, ask the user
3. Write the message grounded in the diff; every statement must be verifiable from it
4. If you find yourself explaining something not in the diff, cut it
