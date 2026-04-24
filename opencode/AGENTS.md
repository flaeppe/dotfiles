# Global Instructions for OpenCode

## Identity
I'm a senior developer working across multiple TypeScript and Python projects.
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

### Be Direct
- Be concise. Skip pleasantries and preamble.
- Don't apologize for mistakes - just fix them and move on.
- Don't repeat my questions back to me.

### Be Concise
- Use code over prose when demonstrating concepts.
- When I ask "why", give me the technical reasoning, not high-level summaries.
- For yes/no questions, lead with the answer.

### Asking Questions
- Only ask when genuinely ambiguous - make reasonable assumptions otherwise.
- Batch related questions together.
- Suggest defaults when asking optional questions.

### Progress Updates
- For multi-step tasks, briefly note what you're doing.
- If something fails, explain why and what you'll try next.

---

## Coding Standards

### General Principles
- Explicit > implicit. Verbose > clever.
- Early returns to reduce nesting. Avoid else after return/throw.
- Parse, don't validate: instead of repeatedly checking raw data, parse it _once_ at the boundary of the system. After parsing, trust the type system.
- Inclusive over exclusive conditions: match what you want, not what you don't. Exclusive checks (`not in`, `!=`) silently pass unknown future values; inclusive checks (`in`, `==`) safely ignore them.
- Prioritize readability. Split functions when it improves clarity, not dogmatically.

### Comments & Docstrings
- Write self-documenting code. Comments explain "why", never "what" the code does.
- Docstrings describe WHAT a function/class does, never HOW it does it internally.
- **No session-context comments** — every comment must make sense to a reader with zero knowledge of the conversation, PR, or task that produced the code. Don't justify design choices by referencing the current session ("we chose X because..." or "this avoids the problem where..."). If the reasoning matters long-term, phrase it as a standalone technical note.
- **No cross-reference assumptions** — don't reference behavior of other modules as justification (e.g. "matches how service B handles this"). That coupling drifts silently when the referenced code changes. State the local reason instead.
- **No diff-relative comments** — never describe what the code replaced (e.g. "batch query instead of row-by-row loop"). The old code won't exist after merge. Describe what the current code does and why, not what it improved upon.
- Remove commented-out code before completing a task.

### Error Handling
- Use specific error types, never generic Error() or Exception().
- Include actionable context in messages.
- Handle errors at appropriate boundaries - don't swallow them.

### Naming
- Descriptive names > abbreviations (i, j in loops, x in lambdas is allowed, but try not to).
- Boolean variables prefixes: `is`, `has`, `should`.
- Functions: verb + noun (`fetchUser`, `validateInput`, `handleSubmit`).

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
- Strict mode always. No `any` unless absolutely necessary.
- `interface` for object shapes, `type` for unions/aliases.
- `unknown` over `any` for truly unknown types.
- Discriminated unions over optional properties.
- Use `satisfies` for type validation with inference.
- Prefer `const` over `let`. Never `var`.

### Python
- Type hints for all function signatures.
- f-strings over .format() or %.
- pathlib over os.path.
- Follow PEP 8.

### Bash/Shell
- `set -euo pipefail` in scripts.
- Quote all variables: "$var".
- Use `[[ ]]` over `[ ]`.

---

## Safety Rules

### NEVER
- Run any destructive commands without approval.
- `rm -rf` on directories.
- Modify .env files without asking.
- Expose secrets in code or logs.
- Destructive DB commands without WHERE clause.
- Deploy to production, or remote environments in general.

### ALWAYS
- Use --dry-run first for destructive operations.
- Verify paths before delete operations.

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

### File Operations
- Use ripgrep (grep tool) for searching, not bash grep.
- When editing files, make minimal targeted changes - don't rewrite entire files.
- Read files before editing to understand context.
- Don't guess paths - use glob to find files.

### Exploration
- Explore codebase before making changes.
- Check for existing similar implementations before writing new code.
- Read test files to understand expected behavior of existing implementations.

---

## Quality Checklist

Before completing any task:
- Verify the code compiles/lints without errors.
- Check for obvious bugs (null checks, edge cases, off-by-one errors).
- Ensure consistent formatting with the rest of the codebase.
- Remove debug statements and commented-out code (see Comments & Docstrings).
