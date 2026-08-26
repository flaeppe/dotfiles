# Spec — pr-session

Not loaded at runtime. Read only when changing this skill.

## Purpose

Drive a local, human-gated PR review: findings become in-code markers, accepted
findings become one commit each on a suggestion stack, artifacts assemble locally,
and nothing leaves the machine until an explicit publish.

## Design intent

- A suggestion stack is usually squashed into the author's branch, so commit
  bodies are a *transient* carrier. Two durable surfaces — code comments (survive
  the squash) and the PR description (outlives the commits) — with commit bodies
  as the carrier between them. Never collapse the two into one.
- **Restraint is a valid result at every output.** An empty analysis, a summary
  that stops after the short version, an absent record. Anything padded to fill a
  template reads as reasoning and is not.
- **Records state decisions, not sessions.** What the reader needs is where things
  stand and what was ruled out — never the order it was arrived at, or that anyone
  changed their mind. Chronology is the main way this skill's outputs bloat.
- Provider/session split: a provider returns findings and performs no effects; every
  effect happens in this skill, once. Keeps conformance cheap for providers.
- Phase B's unit is a **batch**, not a finding. The reviewer's cost is a round, so
  mechanical fixes sweep together in one and findings that must be judged together land
  together; the gate is what has to be in front of the reviewer at once, and hunk
  separability only caps it. Commits stay one per finding.
- The record is **written as the commit message, at implementation time**, and the editor
  commits that file on accept. What the reviewer takes diverges from what was proposed, so
  the message is reconciled against the stack: a file edit while the finding is still
  uncommitted, an amend only once it has landed. Writing it while implementing is what
  leaves nothing unrecorded when a session is abandoned mid-flight.
- Phase C decides, Phase D executes. Anything requiring a judgement belongs in
  `assemble`; `publish` runs `plan.sh` and reports.
- A phase no other phase reads belongs in `references/`, reached by a router line — one
  invocation loads one phase. `help` is the case that holds it: a diagnostic nothing else
  consults, and dead weight in every analyse.
- When changing this skill, repair the line that causes a behaviour before adding a
  rule that argues with it. Two of this file's rules exist because a mandate elsewhere
  said the opposite; a counter-rule twelve lines down loses to the mandate that reads
  first, and leaves the contradiction for the next session to trip over.

## Invariants (never remove or weaken without a human rewrite)

- Never commits on the stack branch — a commit is the reviewer's acceptance.
- Writes nothing outward outside Phase D; never touches the reviewed branch.
- Never tears a session down; `review retire <pr>` is the reviewer's to run.
- Amends are message-only, HEAD-only, and never on a published branch.
- `ask` findings are never implemented.
- Markers never exist in the stack worktree, and never get committed.
- Phases stay separable: `assemble` writes, `publish` sends, and the only thing
  `publish` may regenerate is the stack PR's URL, which cannot exist before it runs.

## Size budget

- Phase A's worst path loads SKILL.md **and** CONTRACT.md together: **≤ 29000 chars**
  for the pair (currently 27749).
- `skill-improver/scripts/measure.sh` reports SKILL.md plus the largest leaf, which is
  no path this skill takes: Phase A pairs SKILL.md with CONTRACT.md, `help` pairs it
  with `references/help.md`. Add the pair by hand.

## Rehaul threshold (refuse and defer to a human rewrite)

- Any change >25% of SKILL.md lines, or to the frontmatter description/scope, or to
  the phase structure, or to an invariant above.
