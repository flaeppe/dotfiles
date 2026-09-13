# Spec — planning skill

**Purpose:** Structure multi-step work into a durable plan artifact so it
survives across PRs and sessions. It plans the work; it does not perform it.

**Two modes (the core design intent):**
- **Multi-file, long-running** — a large effort that evolves over time:
  increments accrue and the plan adapts as reality lands.
- **Single-file** — an item not expected upfront to spawn multiple increments;
  normally shorter and smaller in scope. One document, start to finish.

**Invariants** (a change that violates one → drop it):
- Both modes stay first-class; never collapse to one.
- Full scope is understood before increments are extracted.
- Plan files are append-only by default; rewrite or delete only on explicit
  approval — the sequence is the trace.
- History lives in git (commit messages + `git log`) — no changelog file here.

**Size budget:** 8000 bytes, worst-path load across the skill dir (SKILL.md +
the largest single leaf; there are no leaves today, so SKILL.md is the whole
path). Measure with `wc -c` — bytes, not `wc -m`: the em-dashes make those
differ by ~50, which is enough to read as under when it is over.

Currently 9090 — over the ceiling, knowingly, and queued as
`planning-skill-rehaul` in the plan tree, which carries the reasoning and a
check that reports the figure. The ceiling is never raised to fit whatever was
last added. Trim back or raise it deliberately, and restamp this figure either
way.

**Rehaul threshold:** a change touching >25% of SKILL.md lines, or the
frontmatter description, or the section structure — do it as its own rewrite
session, not a refine.
