---
name: planning
description: Use when planning multi-step work that will span multiple PRs or sessions — covers incremental decomposition, plan file conventions, and chronological trace structure
---

# Planning

## When to Use

- Work that spans multiple PRs or sessions
- Changes touching multiple files, services, or repos
- Anything that isn't a one-shot fix

Do NOT use for trivial single-file changes or quick bug fixes.

## File Conventions

### Location

```
Single-repo work:   <repo>/_private/.plan/<project>/NNN-description.md
Multi-repo work:    ~/anyfin/.plan/<project>/NNN-description.md
```

`<project>` is a short kebab-case name for the effort (e.g., `pydantic-v2`,
`distributed-tracing`, `submission-mode`).

### Numbering

Zero-padded, monotonically increasing: `001`, `002`, `003`, ...

The sequence IS the history. To understand the full picture, start at the
highest number and work backwards.

### Header

Every file starts with:

```markdown
# Title

> **Date:** YYYY-MM-DD
> **Status:** Draft | In Progress | Complete
> **Builds on:** NN-filename.md (if applicable)
> **Next:** NN-filename.md (if known)
> **Repos:** repo1, repo2 (if multi-repo)
```

### File Lifecycle

- **Never delete or rewrite old files** — they are the trace
- **New file for:** new phase, new discovery, significant pivot, execution findings
- **Same file for:** minor status updates only
- Cross-reference between files using relative filenames

## The Decomposition Procedure

This procedure is mandatory for all multi-step work.

### Phase 1: Research & Full Scope → 001

Investigate the problem space. Document:

- Current state of all affected code/services
- The complete set of changes needed to reach the goal
- Risks, dependencies, ordering constraints
- A deployment/execution order rationale

This is the "imagine the finished work" step. Write it as if you're looking
at the completed change with everything done — every file touched, every
behavior changed. The 001 file is the master reference; all subsequent
files build on it.

End 001 with a section that previews the incremental sequence and the
rationale for that ordering.

### Phase 2: Incremental Extraction → 002, 003, ...

From the full scope in 001, extract independently deployable increments.

**The extraction loop:**

1. Identify pieces that form a coherent, standalone change
2. Verify each piece passes the quality criteria (below)
3. After extracting the obvious pieces, re-examine what remains
4. Ask: can restructuring the remaining work unlock more extractions?
5. Repeat until the residual is as small as possible

**Sequencing:** Order increments so each builds on the last. Foundations
first — extract pieces that support future work before the work that
depends on them.

**One file per increment.** Each file documents: what changes, why it's
independent, what it enables for later increments.

### Phase 3: Execution Trace → later files

As work progresses, new files capture what happened:

- Staging findings, test results, unexpected discoveries
- Pivots and adjustments to the original plan
- Post-completion notes and follow-up work

These are the chronological record of the plan meeting reality. They are
not failures — they are expected. Plans change when they meet code.

## Quality Criteria for Each Increment

Every extracted increment MUST satisfy ALL of these:

### Logical

It addresses a coherent concern. A reviewer understands the "why" without
needing the master plan. If the only way to describe the PR is "part 1 of
N", it's not a good extraction — each increment has its own reason to
exist.

Don't extract random mechanical changes (renames, moves, reformats) just
to hit a line count. If it doesn't make sense on its own, it's not ready
to be extracted.

### Independent

It compiles, passes tests, and can be deployed on its own. No increment
leaves the codebase in a broken or half-migrated state.

### Enabling

It supports future increments. We do foundational work first — the kind
of change that makes subsequent work easier, smaller, or possible.

### Reviewable

Target ~200 lines of business logic per increment. Tests and test fixtures
don't count toward this limit — they can always make the diff larger.

If a coherent change exceeds ~200 lines, that's acceptable. Coherence
always wins over size. But if it's large, ask whether it can be split
further without losing coherence.

### Boring

No surprises. No hot swaps. No big bangs. The work is incremental, silent,
well-thought-out. Each increment looks like a natural, obvious change in
isolation.

## Anti-Patterns

- **Mechanical splits:** Don't extract random renames or moves just to hit
  a line count. Every increment must make sense on its own.
- **Monolith plans:** Don't write one giant plan file. Split into research
  (001) and increments (002+).
- **Retroactive editing:** Don't modify old plan files to match new reality.
  Add new files that document what changed and why.
- **Skipping research:** Don't jump to increments without understanding the
  full scope first. The 001 file prevents tunnel vision.
- **Over-planning:** Don't plan 20 increments upfront. Plan the first 3-5
  in detail, sketch the rest. Refine as you execute.

## Resuming Existing Plans

When continuing work on an existing plan:

1. Read existing files, highest number first
2. Understand current state and what's been completed
3. Add a new file for the next phase of work
4. Reference what it builds on
