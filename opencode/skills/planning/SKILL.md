---
name: planning
description: Use when planning multi-step work that will span multiple PRs or sessions — covers incremental decomposition, plan file conventions, and chronological trace structure
user-invocable: true
---

# Planning

## When to Use

- Work that spans multiple PRs or sessions
- Changes touching multiple files, services, or repos
- Anything that isn't a one-shot fix

Do NOT use for trivial single-file changes or quick bug fixes.

## File Conventions

### Location

Every plan lives in one tree, never inside a work checkout. The repository the
work belongs to picks the directory — `_cross` when it belongs to several — and
the plan's shape picks what sits under it:

```
Multi-file:   ~/.plan/<repo>/<project>/NNN-description.md
Single-file:  ~/.plan/<repo>/description.md
Multi-repo:   ~/.plan/_cross/ + either shape
```

`<project>` is a short kebab-case name for the effort (e.g., `pydantic-v2`,
`distributed-tracing`, `submission-mode`): a directory per effort, a file per
increment. A single-file plan is one document — no directory, no number.

### Numbering

Zero-padded, monotonically increasing: `001`, `002`, `003`, ...

A number is a position in a series, so it belongs only inside a `<project>/`
directory — a flat file has no series to be second in. A single-file plan that
grows increments gets a directory and moves in as `001`.

The sequence IS the history. To understand the full picture, start at the
highest number and work backwards.

### Header

Every file starts with YAML frontmatter, before the title:

```markdown
---
status: Draft | In Progress | Complete | Deferred | Superseded | Abandoned
category: code | docs | ticket | record
services: [repo, other-repo@6537]
verified: YYYY-MM-DD
date: YYYY-MM-DD
builds_on: NNN-filename.md
next: NNN-filename.md
---

# Title
```

| field | rule |
| --- | --- |
| `status` | one of those six words, nothing else — any nuance goes in `status_note` |
| `services` | every repo the work touches, not just the one it is filed under |
| `@<ref>` | the PR or SHA that carried it. Never a branch — branches get deleted |
| `verified` | date the status was last checked against reality |
| `review` | why it could not be settled. Replaces `verified`; never sits beside it |

- A ref hangs off its service because a PR number only resolves next to a repo.
- `verified` is what makes drift detectable: a status is a claim, a status plus
  a date is a claim with an age.
- **Every write restamps `verified` to today** — a PreToolUse hook refuses the
  edit otherwise. Touching the file means you read it, so say what you found.

### Reading a series

To see the state of a whole effort without opening every file:

```
~/.plan/bin/plan-status ~/.plan/<repo>/<project>
~/.plan/bin/plan-status --stale 30 ~/.plan
```

It reads frontmatter only, so pointing it at the whole tree is cheap. `--stale`
lists what has gone unverified and exits non-zero, so it works as a check.

### File Lifecycle

- **Never delete or rewrite old files** — they are the trace
- **Rewrite exception:** revise a file in place only on explicit approval —
  the default stays append-only
- **New file for:** new phase, new discovery, significant pivot, execution findings
- **Same file for:** minor status updates only
- Cross-reference between files using relative filenames

## The Decomposition Procedure

This procedure is mandatory for all multi-step work. First choose the plan's
**shape**: **single-file** for a single design plus a mechanical rollout over
similar items (rollout as a checklist, no 002+); **multi-file** (001 + a file
per increment) when increments each carry distinct design worth its own document.

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

### Phase 2: Incremental Extraction → 002, 003, … (single-file mode: a checklist in the one document)

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

**Merge-gates vs. try-out track:** separate what truly must land on the
stable branch first (a shared platform surface, someone else's base) from
what can be proven on a deploy-free surface (dev sandbox, remote preview,
feature flag). Keep the merge-gated set minimal — batch same-surface
prerequisites into one increment — and route the riskiest architectural
bet through the try-out track first; merges then harvest proven slices.
A sequence where several increments must merge before the first real
feedback arrives is a waterfall in disguise.

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

Every extracted increment MUST satisfy Logical, Independent, Enabling and
Boring. Reviewable is a target coherence may override:

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

- **Capability slicing:** Don't cut one increment per feature when they're
  all small derivations over the same surface. Slice by surface — what must
  build and merge together. Fewer coherent increments beat a long queue
  that serializes feedback.
- **Monolith plans:** In multi-file mode, don't dump the whole effort in 001 — split.
- **Skipping research:** Don't jump to increments without understanding the
  full scope first. The 001 file prevents tunnel vision.
- **Over-planning:** Don't plan 20 increments upfront. Plan the first 3-5
  in detail, sketch the rest. Refine as you execute.

## Resuming Existing Plans

Before starting, check whether the effort already has files under its
repository's directory, or under `_cross/`.

Start with `plan-status` on that directory — it gives you the whole
series' state in one pass, and tells you which files are stale or carry a
`review:` flag before you spend anything reading them. Then read the files
themselves, highest number first. Then:

1. Understand what's been completed and what remains
2. Add a new file for the next phase of work
3. Reference what it builds on
4. Restamp `verified` on any file whose status you checked along the way —
   including ones you did not otherwise change. A status you confirmed is a
   result worth recording, not just a status you corrected.
