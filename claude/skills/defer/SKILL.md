---
name: defer
description: Capture deferrable work from the live session as a self-contained plan file to resume in a clean session later
user-invocable: true
---

Capture the work described below as ONE self-contained plan file, so I can drop
this session and resume cold later. You are writing a capture file, not doing
the work and not planning the full breakdown.

$ARGUMENTS

## What this is (and isn't)

A `defer` is a single lightweight file that snapshots one piece of deferrable
work. It is NOT a `planning` decomposition — do not run Phase 1–3, do not split
into increments, do not imagine the finished work across multiple PRs. One task,
one file.

The whole point is that THIS session has context a fresh one won't. Pull that
context from here — don't ask me to re-explain what's already on screen.

## Before writing: check for an existing plan

Planning docs are ingested into the kb, so search there first to avoid
duplicating something I already captured. Planning docs are excluded from kb
results by default — pass `include=["plans"]`.

**Two queries, then one filename check.** One query is not enough. A single long
query mixing the service, the artefact format and the failure shape ranks on
whichever axis carries the most lexical mass, and the domain lens files win that
fight every time — so an existing plan about the *same failure on a different
service* stays buried even when your query did contain the mechanism words.

1. **Artefact/service** — what you'd naturally type.
   `kb_find(query="<service> <artefact> <task in a few words>", include=["plans"])`
2. **Failure shape, with the service and format words deleted.** Those words
   don't merely fail to help here — they suppress the cross-service matches this
   step exists to find.
   `kb_find(query="<what goes wrong, mechanism only>", include=["plans"])`
3. **Filename substring**, deterministic and unranked. Plan directories are named
   after their mechanism, so this surfaces siblings that relevance ordering
   buries. `kb_files(pattern="<mechanism keyword>")`

**Stop when (2) returns nothing (1) didn't.** That is the bound: you are covering
two orthogonal axes once each plus a free exact check — not enumerating
mechanisms.

If a similar or identical plan turns up, don't silently write a new file.
Present the match briefly — title, path, status, and a one-line gist (enough to
recognize it, not the whole file) — then let me choose, and **recommend one**
with a short reason:

- **Extend** — add a new `NNN` file in that plan's directory that builds on it
  (set `Builds on:` in the header).
- **Amend** — fold the new detail into the existing file.
- **Separate** — this is genuinely distinct; create a fresh plan.

Only when the search comes back clean (or I pick "separate") do you write a new
file.

## File location, numbering, and header

Follow the `planning` skill's **File Conventions** exactly — location
(single- vs multi-repo), `NNN-description.md` numbering, and the header block.
Don't restate or fork those rules here; planning is the single source of truth
for where the file goes and what the header looks like. Resolve single- vs
multi-repo from the current branch/repo and pick the next `NNN` the same way
planning does.

The only fixed difference: a deferred file always starts at **Status: Draft**.

## What to capture

Just enough to resume cold — no more. This is on-the-fly capture, not a spec.
Include only the sections that carry weight:

- **Task** — the one thing to be done, stated plainly.
- **Context the fresh session won't have** — the load-bearing bits: relevant
  files/paths and symbols, the current state of that code, any decision already
  made (and what it rules out). This is the part worth the most; mine it from
  the live session.
- **Why deferred** — only if it's substantive (a blocker, a dependency, a
  sequencing reason). Skip it if the answer is just "we're doing something else
  right now."
- **Done when** — what success looks like, observably.

Cut anything a competent fresh session would figure out on its own. Don't pad to
look thorough.

## Process

1. Search the kb for an existing plan on this work — both queries plus the
   filename check above, stopping on convergence. If one matches, present it and
   let me choose extend/amend/separate (recommend one); only continue to a new
   file if it's clean or I pick separate.
2. Resolve current branch/repo to pick the location and next `NNN` (per planning).
3. Write the one file with planning's header block, Status: Draft.
4. Report the path. The file alone must be enough to resume in a clean session —
   if you couldn't resume from it cold, add the missing load-bearing detail.
