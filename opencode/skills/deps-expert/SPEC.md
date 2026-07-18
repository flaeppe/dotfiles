# Spec — deps-expert skill

**Purpose:** Treat the whole codebase as one dependency graph — named nodes
(functions, types, modules, packages) joined by edges (imports, calls, type
references, throws) — and audit that graph for coupling, layer boundaries,
awareness, and abstraction quality. Finds where the graph is wrong, names the
violation as an edge, and shows the corrected shape. It analyses; it does not
refactor.

**Core design intent — one graph, one lens, two modes:**
- **One graph, every altitude.** Function-to-function, type-to-type,
  module-to-module, and codebase-to-3rd-party are the *same* graph at different
  zoom levels. There is no separate doctrine per level — only the nodes differ.
- **The awareness lens is the whole doctrine.** Every edge reduces to one
  question: "is `from` aware of `to`, and should it be?" A violation is always
  an edge that shouldn't exist (or points the wrong way); a fix always moves,
  removes, or redirects an edge. Findings are phrased as edges, never as vague
  coupling.
- **Diff-Scoped** — audit only the new edges a diff introduces; speed first.
- **Full Audit** — derive the whole graph and find every category of violation.

**Invariants** (a change that violates one → drop it):
- The graph is the model and the awareness lens is the single doctrine, applied
  at every altitude; never fork into per-level doctrines.
- Both modes stay first-class; never collapse to one.
- Every finding is a concrete edge — this name depends on that name, in this
  module — and cites the rule it breaks. No abstract "improve coupling."
- No abstraction is proposed unless it resolves a named violation. No
  speculative interfaces "for flexibility."
- Analysis only: findings + corrected-shape recommendations, never a rewrite.
- History lives in git (commit messages + `git log`) — no changelog file here.

**Size budget:** 14000 chars, worst-path load. Single-file skill (no leaves),
so worst-path = SKILL.md. Currently 13688; check with `wc -c SKILL.md`.
(Raised 13500→14000 to fit the persona spine — report-with-integrity + grade
by the finding itself, not its reach or the cost/ownership of the fix.)

**Rehaul threshold:** a change touching >25% of SKILL.md lines, or the
frontmatter description, or the section structure — do it as its own rewrite
session, not a refine.
