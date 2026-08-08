# Spec — skill-improver

Not loaded at runtime. Read only when changing this skill (it dogfoods its own
rules).

## Purpose

Refine a skill exercised in the current session, within hard bounds. Propose,
never apply unprompted. Bias toward proposing nothing.

## Invariants (never remove or weaken without a human rewrite)

- Human-gated: never writes a skill file without explicit approval.
- Never improves itself in the same run (no self-reference).
- Never does a rehaul; refuses and defers to a human rewrite or a new skill.
- Judges against the target skill's spec + whole content, not the session.
- Carries no project- or organization-specific phrasing — must stay portable
  to a global location.

## Size budget

- Worst-path load ≤ 9000 chars. Measured by `scripts/measure.sh` on this dir.

## Rehaul threshold (refuse and defer)

- Any change >25% of SKILL.md lines, or to the frontmatter description/scope, or
  to an invariant above.
