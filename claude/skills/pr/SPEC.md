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
  not the floor. Observed: a 58-line body on a `+58/-4` diff, carrying five
  headings, a `## Testing` section and a "findings from building it" section —
  every one of them already forbidden by SKILL.md's rules. The rules were
  present; nothing checked them, so the length gate exists to add the check
  rather than re-reading the rules.
- **The reader has GitHub and this repo, nothing else.** A path outside the
  repo, a plan file's name or number, or the name of a tool or session that
  did the work resolves for no one who opens the PR. A `PreToolUse` hook
  (`gh-pr-body-guard`, beside `git-local-path-guard`) enforces this and the
  length gate mechanically: it refuses `gh pr create`/`gh pr edit` unless the
  body's last line is the marker `<!-- pr:v1 -->`, which only this skill
  writes, and then lints the marked body against these invariants.
- **No code-internal vocabulary in reviewer-facing text**, title and in-diff UI
  strings included. Identifiers are cited in backticks, never conjugated into
  English. Measured origin: the only wording complaint in two weeks was
  "legs", "fold" and "delta" used as common nouns — "This PR title
  makes no sense ... speak in NORMAL language" (user, 2026-09-02). Importance
  adjectives (comprehensive, robust, seamless) drew **zero** complaints in the
  same window; do not add a rule against them without evidence.

**Size budget:** 5800 chars for SKILL.md (no leaves). Grown deliberately from
792 in three steps: the prohibitions plus two real PR bodies as worked
examples; the plain-language table of real before/after corrections; the
local-machine-resolution rule and the marker requirement, paid for by moving
the length gate's worked incident here. Showing the target changes output
where describing it does not, so **both example sets are load-bearing — trim
prose before trimming them.** Currently 5645 (measured `wc -c`, not the 3810
this file previously claimed — restate this number whenever SKILL.md changes,
it drifts silently otherwise). The 3600 figure was guessed before the
plain-language table existed; raised each time on purpose, rather than shaving
the rules until they read as slogans.

**Rehaul threshold:** a change touching >25% of SKILL.md lines, the frontmatter
description, or the section structure — its own rewrite session, not a refine.
