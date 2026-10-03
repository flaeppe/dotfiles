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
type: Research | Decision | Build | Review | Monitoring | Seed | Record | Reference
summary: one line, at most 140 characters
journal: <journal-key>
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
| `type` | required; exactly one of the eight values, TitleCase. `category` is retired and refused, naming the `type` it maps to |
| `summary` | optional; one line, at most 140 characters |
| `journal` | optional; the key of the journal the plan belongs to |
| `services` | every repo the work touches, not just the one it is filed under |
| `@<ref>` | the PR or SHA that carried it. Never a branch — branches get deleted |
| `verified` | date the status was last checked against reality |
| `review` | why it could not be settled. Replaces `verified`; never sits beside it |

- `type` says what the file is for. `Research` finds out, `Decision` chooses,
  `Build` changes code or config, `Review` answers a review, `Monitoring`
  watches something after a change, `Seed` is a prompt that starts a session,
  `Record` is an append-only ledger or log, `Reference` is a fact sheet.
- `Record` and `Reference` are never "done", so they are exempt from the
  done-when requirement.
- Files in the vault drafts directories keep their own vault `type` values; the
  closed set does not apply to them, and `me plans check-file` skips the check
  for those paths.
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

### Checks

`me plans verify` runs every `(CHECK: <command>)` line in a plan, so a check
answers the claim it sits on — usually a Done-when item.

**A check must print its answer and exit 0 in both states.** A non-zero exit is
classed "could not run", so a `grep -c` asserting a string will exist can only
ever say yes or unrunnable — never "not yet".

```
file content   awk '/mark_a/{a++} /mark_b/{b++} END{print "a="a+0" b="b+0}' /abs/path
a PR's state   gh pr view 367 --repo owner/repo --json state -q .state
on a git ref   no good shape — check the PR that puts the content there
```

| how it lies | |
| --- | --- |
| no shell | a pipe or `&&` makes it unrunnable — one process only |
| no expansion | `~` and `$HOME` both fail; absolute paths only |
| no baseline | a count on a string already on the base branch reports done before the work starts |
| wrong target | `gh pr list --search "<title>"` matched an unrelated merged PR. Address a PR by number |

The awk shape fixes the first two. Picking markers new to the work is yours.

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

Write it as if looking at the completed change — every file touched, every
behavior changed. 001 is the master reference. End it with a preview of the
incremental sequence and why that order.

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

New files capture what happened: staging findings, test results, unexpected
discoveries, pivots, follow-up work. A plan meeting reality is expected, not a
failure.

## Quality Criteria for Each Increment

Every extracted increment MUST satisfy Logical, Independent, Enabling and
Boring. Reviewable is a target coherence may override:

### Logical

It addresses a coherent concern a reviewer understands without the master
plan. If the only way to describe the PR is "part 1 of N", it is not a good
extraction. Don't slice out mechanical changes (renames, moves, reformats) to
hit a line count.

### Independent

It compiles, passes tests, and can be deployed on its own. No increment
leaves the codebase in a broken or half-migrated state.

### Enabling

It supports future increments. We do foundational work first — the kind
of change that makes subsequent work easier, smaller, or possible.

### Reviewable

Target ~200 lines of business logic per increment; tests and fixtures don't
count. Coherence wins over size — but if a change is large, ask whether it
splits without losing it.

### Boring

No hot swaps, no big bangs. Each increment looks like a natural, obvious
change in isolation.

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

Start with `plan-status` on that directory: the whole series' state in one
pass, including what is stale or carries a `review:` flag. Then read the files
themselves, highest number first. Then:

1. Understand what's been completed and what remains
2. Add a new file for the next phase of work
3. Reference what it builds on
4. Restamp `verified` on any file whose status you checked along the way —
   including ones you did not otherwise change. A status you confirmed is a
   result worth recording, not just a status you corrected.
