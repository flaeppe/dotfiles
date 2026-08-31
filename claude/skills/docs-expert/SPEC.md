# Spec — docs-expert skill

**Purpose:** Produce documentation that survives years of refactoring — module
READMEs, mermaid diagrams, docstrings, inline comments — and audit existing
documentation against the same bar. Two modes: turning a chronological planning
record into docs that stand alone, and auditing docstrings/comments in changed
code. It documents; it does not refactor the code it documents.

**Core design intent — contract, reason, altitude:**
- **A docstring is a contract; a comment is a reason.** The two failure modes
  this skill exists to prevent are docstrings that summarise implementation and
  comments that reference anything outside the file. Every rule serves one of
  those two. The seam between them: a mechanism displaced out of a docstring
  survives in the body only by becoming a reason — why this mechanism, not what
  its steps are. Otherwise the two rules cancel, one creating what the other
  deletes.
- **Altitude is the placement doctrine.** Root vs nested README, system vs
  module diagram, docstring vs body comment — one question at three zoom
  levels: what is this artifact's level, and does the content belong at it?
  Content that sits at the wrong level is *moved* there, not deleted.
- **Standing alone is the acceptance test.** If removing the planning files,
  the PR, or the conversation breaks the text, the text is wrong.

**Invariants** (a change that violates one → drop it):
- Docstrings describe WHAT; HOW moves into the body — as a reason — rather than
  being deleted.
- Comments refer only to what is visible in the file — no callers, no sibling
  modules, no prior implementations, no session context.
- A rewrite must be justified by a named rule. Wording alone is not a defect,
  and a rewrite carries over every specific the old text held — churn and lost
  detail are both regressions the skill must not manufacture.
- Never invent rationale; flag what cannot be inferred from the code and plans.
- Never document code that does not exist yet.
- Both modes stay first-class; never collapse to one.
- History lives in git (commit messages + `git log`) — no changelog file here.

**Size budget:** 14000 chars, worst-path load. Single-file skill (no leaves),
so worst-path = SKILL.md. Currently 13898; measure with skill-improver's
`scripts/measure.sh`.

**Rehaul threshold:** a change touching >25% of SKILL.md lines (~75), or the
frontmatter description, or the section structure — do it as its own rewrite
session, not a refine.
