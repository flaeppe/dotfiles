# Spec — pr skill

**Purpose:** Turn a pushed branch into a PR whose description earns every line.
It writes the title and body; it does not review the code, fix checks, or decide
whether the work is ready.

**Design intent:** the description is for the reviewer's decision, not a record
of the author's effort. Three questions answer it — what changed, why it had to,
what to push back on — and everything else is either already on the page (the
diff, the check runs, the commit list) or is padding.

**Invariants** (a change that violates one → drop it):
- **Never claims automated verification.** Tests, lint, typecheck and CI report
  themselves; asserting them is bloat when true and a lie when premature. This
  is the invariant the skill exists to hold — it was the previous version's
  "include testing notes if relevant" that produced the bloat, and it worked:
  a Testing/Verification/Test-plan heading appears in **54 of 76** PRs over two
  weeks, against only 8 that state a pass claim in prose.
- **No mandated section structure**, and no ban on one either. Measured across
  76 PRs (2026-08-20..09-02): `## Summary` appears in 49 and its content is
  rationale, not a diff restatement — the three best bodies all use it. What is
  actually wrong is a heading over a **one-line** section (19 instances).
- **Title rules live in the `commit` skill**, never duplicated here. A PR title
  is a commit subject; two copies drift.
- **Length tracks the change, not the effort.** Under 10 lines is the default,
  not the floor.
- **No code-internal vocabulary in reviewer-facing text**, title and in-diff UI
  strings included. Identifiers are cited in backticks, never conjugated into
  English. Measured origin: the only wording complaint in two weeks of nexus
  sessions was "legs", "fold" and "delta" used as common nouns — "This PR title
  makes no sense ... speak in NORMAL language" (user, 2026-09-02). Importance
  adjectives (comprehensive, robust, seamless) drew **zero** complaints in the
  same window; do not add a rule against them without evidence.

**Size budget:** 3900 chars for SKILL.md (no leaves). Grown deliberately from
792 in two steps: the prohibitions plus two real PR bodies as worked examples,
then the plain-language table of real before/after corrections. Showing the
target changes output where describing it does not, so **both example sets are
load-bearing — trim prose before trimming them.** Currently 3810. The 3600
figure was guessed before the plain-language table existed; raised once, on
purpose, rather than shaving the rules until they read as slogans.

**Rehaul threshold:** a change touching >25% of SKILL.md lines, the frontmatter
description, or the section structure — its own rewrite session, not a refine.
