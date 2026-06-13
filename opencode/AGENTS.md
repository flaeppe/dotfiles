# Global Instructions for OpenCode

## Identity
I'm a senior developer working across multiple TypeScript, Python and Golang projects.
Treat me as experienced - skip beginner explanations.

---

## Environment

- **macOS with Nix, Home Manager, and direnv.** All project toolchains (Python, Node, compilers, etc.) are managed through Nix flakes with direnv integration.
- To find the active toolchain for a project, check `.envrc` and `flake.nix` / `flake.lock` in the project root.
- Run `direnv status` to see the currently active environment and its source `.envrc`.
- The correct binary versions are those activated by direnv in the project's shell environment — these are the versions in PATH when the shell is inside the project directory.
- If a binary is missing from PATH, it likely means the shell isn't inside a direnv-managed project directory, or `direnv allow` hasn't been run yet.

---

## Communication Style

- Be concise; skip pleasantries and preamble. Don't apologize for mistakes — fix them and move on. Don't repeat my questions back to me.
- Use code over prose when demonstrating concepts. For yes/no questions, lead with the answer. When I ask "why", give me the technical reasoning, not a high-level summary.
- Only ask when genuinely ambiguous — otherwise make reasonable assumptions and state them. Batch related questions; suggest a default for each.

---

## Coding Standards

### General Principles
- Explicit > implicit. Verbose > clever.
- Early returns to reduce nesting. Avoid else after return/throw.
- Parse, don't validate: instead of repeatedly checking raw data, parse it _once_ at the boundary of the system. After parsing, trust the type system.
- Inclusive over exclusive conditions: match what you want, not what you don't. Exclusive checks (`not in`, `!=`) silently pass unknown future values; inclusive checks (`in`, `==`) safely ignore them.
- Prioritize readability. Split functions when it improves clarity, not dogmatically.

### Minimalism

The laziest solution that actually works is the right one. Lazy means
efficient, not careless — the best code is the code never written. This
governs *what* you build; it never licenses unreadable code (see Readability
below).

**The ladder.** Before writing code, stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need → skip it, say so in one line. (YAGNI)
2. **Standard library does it?** Use it.
3. **Native platform feature covers it?** `<input type="date">` over a picker lib, CSS over JS, a DB constraint over app code.
4. **Already-installed dependency solves it?** Use it. Never add a new dependency for what a few lines do.
5. **Can it be one line?** One line — if it stays readable (see below).
6. **Only then:** the minimum code that works.

The ladder is a reflex, not a research project. Two rungs both hold → take the
higher one and move on.

**Rules:**
- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- No scaffolding "for later" — later can scaffold for itself.
- Deletion over addition. Fewest files, shortest working diff.
- Two stdlib options the same size? Take the one that's correct on edge cases — lazy means writing less code, not picking the flimsier algorithm.
- Complex request you can partly default? Ship the lazy version and question the rest in the same response ("Did X; Y covers it. Need full X? Say so."). Don't stall on something you can sensibly default.
- A deliberate simplification with a known ceiling (global lock, O(n²) scan, naive heuristic) gets a comment naming the ceiling and the upgrade path — e.g. `# global lock; per-account locks if throughput matters`. This is a "why" comment under the Comments rules, not a special marker.

**Readability is not negotiable.** Minimal means fewer things built — fewer
files, fewer abstractions, fewer dependencies, less dead flexibility. It does
**not** mean dense. Never compress logic into a clever one-liner someone has to
decode at 3am, and never reach for single-letter or cryptic names as a shortcut
for thinking about the right one (the `i`/`j` loop and `x` lambda exceptions
from Naming still apply, nothing more). When "shortest" and "readable" collide,
"Verbose > clever" wins: the shortest diff that stays obvious beats a shorter
one that doesn't. Boring over clever.

**Output (when delivering a change).** Lead with the code, then at most a few
lines — what you skipped and when to add it (`[code] → skipped: X, add when Y.`).
Don't precede a small change with an essay or a feature tour; every paragraph
spent defending a simplification is complexity smuggled back in as prose. This
is delivery discipline only — it never overrides "when I ask why, give the
technical reasoning"; a direct question still gets a real answer.

**When not to simplify.** Never strip input validation at trust boundaries,
error handling that prevents data loss, security, or accessibility basics — and
never drop anything explicitly requested (if I insist on the full version,
build it, no re-arguing). Testing follows the Testing section, not a lighter
bar. YAGNI does not apply to safety.

### Boundary Layers

**Business logic must not live in boundary/protocol/schema layers.** Handlers,
controllers, resolvers, and schema definitions are glue — they are not where
logic belongs. Unless explicitly told otherwise, design systems so that:

1. **Business logic exists as a plain language-level API** — functions and classes
   that can be called without any protocol awareness. This is the source of truth.
2. **Boundary layers do exactly two things:**
   - Parse foreign data (request bodies, messages, events) into the types the
     business logic expects.
   - Convert errors propagating from business logic into protocol-appropriate
     responses (HTTP status codes, GraphQL errors, gRPC status, etc.).

The litmus test: adding a new exposure layer (e.g. REST, CLI, message consumer)
should be trivial — just parsing and error mapping, no logic duplication.

### Comments & Docstrings
- Write self-documenting code. Comments explain "why", never "what" the code does.
- Docstrings describe WHAT a function/class does, never HOW it does it internally.
  A docstring is a contract: inputs, outputs, side effects. Nothing else — no
  implementation details, algorithms, internal mechanics, or design rationale.
  Keep them terse. If the function name and type signature already say it, skip
  the docstring entirely.

  BAD: "Uses a Redis sorted set where each request is stored as a member scored
  by its timestamp. On each check the window is trimmed and the remaining
  cardinality is compared against the limit."
  GOOD: "Sliding-window rate limiter. Enforces a maximum request count per
  identifier within a rolling time window."
- **No session-context comments** — every comment must make sense to a reader with zero knowledge of the conversation, PR, or task that produced the code. Don't justify design choices by referencing the current session ("we chose X because..." or "this avoids the problem where..."). If the reasoning matters long-term, phrase it as a standalone technical note.
- **No cross-reference assumptions** — don't reference behavior of other modules as justification (e.g. "matches how service B handles this"). That coupling drifts silently when the referenced code changes. State the local reason instead.
- **No diff-relative comments** — never describe what the code replaced (e.g. "batch query instead of row-by-row loop"). The old code won't exist after merge. Describe what the current code does and why, not what it improved upon.
- Remove debug statements and commented-out code before completing a task.

### Naming
- Descriptive names over abbreviations (`i`/`j` loop counters and `x` lambdas excepted, but avoid otherwise).

### Testing
- Write tests for new functionality when a test framework exists.
- Prefer integration tests over unit tests for business logic.
- Don't mock, design code to use dependency injection, unless unit testing (injectable) client implementations.

### Working in Existing Codebases

**These guidelines apply to all code you write.** When existing code has poor patterns:

- **Write new code correctly** - don't mimic bad patterns just because they exist
- **Don't refactor unprompted** - leave existing bad code alone unless asked
- **Minimize interaction with bad patterns** - isolate them, don't spread them
- **No consistency excuse** - better code > consistent bad code

---

## Language-Specific

### TypeScript
- Discriminated unions over optional properties.
- `satisfies` for type validation with inference.

---

## Safety Rules

- Never deploy to production, or remote environments in general.
- Modify `.env` files only after asking.
- Never run destructive DB commands without a WHERE clause.

---

## Verifying Code Origin

**Never assume code is "old", "pre-existing", or "legacy" without git verification.** Comments and user framing can be wrong - code labeled "old" might have been added on the current branch.

Before treating code as old/legacy, verify:
```bash
# Check base branch (main or master)
git diff main...HEAD -- path/to/file   # What's new on this branch
git diff HEAD -- path/to/file          # Uncommitted changes
```

If unsure about base branch, **ASK**.

**"Old" = exists in base branch. "New" = only in diff from base.**

---

## Tool Preferences

### Exploration
- Check for an existing implementation before writing new code; read the tests to learn expected behavior.

### Knowledge Base (kb)
My work documents are indexed in a local knowledge base, exposed as the `kb`
MCP server (`kb_find`: hybrid semantic search). It holds whatever I decide to
make searchable - e.g. repo docs/READMEs, the payments inventory, external
integration docs, planning documents. When the tool is available:

- Search it before answering questions about prior decisions, existing
  documentation, integrations, "where is X", or "do we support X" - don't
  answer such questions from memory alone.
- It complements code exploration: kb carries the documented intent and
  context around the code (and around external parties the code talks to),
  while codebase-memory tools carry the code structure itself. When working
  in a repo, a kb search scoped to it (e.g. `tags=["repo:api"]`) can surface
  context the code doesn't show.
- `service:<name>` tags join external specs with the implementation notes
  that integrate against them (the tag appears on both sides). For
  spec-vs-implementation questions ("do we follow X", gap analysis), filter
  on the service tag (e.g. `tags=["service:seb-camt"]`) to retrieve the spec
  and our documented reality together.
- Results are chunks with metadata; read the file at `path` when the chunk
  isn't enough. Files on disk are the source of truth.
- Planning documents are excluded from results by default; pass
  `include=["plans"]` when asked about plans, and always check for existing
  plans before creating a new planning document.
