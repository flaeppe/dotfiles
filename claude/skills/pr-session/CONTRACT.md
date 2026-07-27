# The `.review/` contract

The boundary between a **provider** (whatever analyses a PR) and the **session**
(the editor tooling that curates, implements and ships). Either side can be
replaced without the other knowing, as long as this holds.

This file is self-contained: a provider can be pointed at it alone.

## What a provider is

Anything that reads a pull request and produces findings — the built-in analysis
in `SKILL.md`, or a domain-specific skill named via `--analysis <skill>`. A
provider never knows it is being consumed by a session.

## Where it runs

Inside a **review worktree**: a directory containing `.review/session.json`, with
the PR head checked out detached.

```json
{
  "pr": 4821, "title": "...", "url": "...", "repo": "api", "role": "review",
  "head_branch": "feat/x", "base_branch": "master",
  "pr_head": "<sha>", "merge_base": "<sha>",
  "stack_branch": "review-suggestions/4821",
  "review_worktree": "/…/.worktrees/review/4821/head",
  "stack_worktree":  "/…/.worktrees/review/4821/stack",
  "review_socket": "/tmp/nvim-review-api-4821.sock",
  "stack_socket":  "/tmp/nvim-stack-api-4821.sock"
}
```

## Obligations

A provider MUST:

1. **Read the diff from commits, never the working tree** —
   `git diff <merge_base>...<pr_head>`. The reviewer's worktree may be dirty with
   markers and scratch edits at any time; pinning the input to immutable commits
   is what makes analysis idempotent and re-runnable mid-session.
2. **Write `.review/order.json`** (below).
3. **Insert draft `REVIEW[n]` markers** at the sites its findings concern.
4. **Write `.review/summary.md`** — the reasoning behind the markers as standalone
   prose: answer first, then 2–4 themes grouped by cause, then where to start. At most
   500 words, and no code, paths or identifiers; the markers carry those. It is
   embedded at the top of `findings.md`, so it introduces the findings rather than
   restating them.
5. **Refresh the editor** afterwards, if a socket is live:
   `nvim --server <review_socket> --remote-send '<Cmd>checktime<CR>'`
   Buffers do not auto-reload, so markers written to disk are invisible until
   this runs.

A provider MUST NOT:

- Modify any source file except to insert marker lines.
- Touch the stack worktree, commit, push, or call `gh` to write anything.
- Analyse, report, revert or otherwise act on **unstaged non-marker changes** in
  the review worktree. Those are the reviewer's scratch work and are invisible to
  the review by design.
- Delete or renumber markers it did not write. Ids are identity: gaps are normal
  and renumbering breaks references already made elsewhere.

A provider MAY write `.review/policy.json` (below).

## `order.json`

The order to read the change in, and why. `why` becomes the quickfix entry text,
so the reasoning is visible while walking it.

**Every changed file gets an entry** — one per file in
`git diff --name-only <merge_base>...<pr_head>`, including files you found nothing
in. This is the reviewer's route through the whole change, not an index of your
findings: a file you had no comment on still has to be read, and its absence
would silently shrink the PR. Say so in `why` when that is the case ("no findings;
read to confirm the rename is mechanical").

```json
{
  "pr": 4821,
  "entries": [
    { "file": "src/handler.go", "lnum": 42,
      "why": "entry point — decides which path the rest of the diff takes" },
    { "file": "src/domain/loan.go",
      "why": "the invariant the handler leans on; read second or the handler looks fine" },
    { "file": "src/domain/fixtures.go", "context": true,
      "why": "not in this PR — where the capability the diff works around would live" }
  ]
}
```

Paths are relative to the review worktree. `lnum` defaults to 1.

A file **outside** the diff may be included when reading it is genuinely needed,
but it MUST carry `"context": true`. Unmarked entries are read as the PR's own
files, and an unchanged file smuggled in among them misrepresents how large the
change is.

## Markers

```
REVIEW[<id>]: <text>       a finding; how to raise it is decided later
REVIEW[<id>]fix: <text>    should become code in the suggestion stack
REVIEW[<id>]ask: <text>    a question for the author; never a code change
REVIEW[<id>]note: <text>   private to the reviewer; never reported
REVIEW[<id>]               a back-reference: another site for finding <id>
```

Rules:

- One line, in the file's own comment syntax, directly above the code it
  concerns, at that line's indentation.
- Ids are unique across the whole worktree and allocated from
  `max(existing) + 1`.
- One finding at several sites: give the body once, use bare back-references for
  the rest. That is what turns "wrong in six places" into one finding.
- Choose the kind honestly. `fix` claims the fix is known and mechanical;
  a plain finding says it needs judgment; `ask` says there is no change to make
  until the author answers.

Markers are never committed. The review worktree is deleted when the review
ships.

## `policy.json` (optional)

Ship constraints, as data. A provider with house rules declares them here rather
than embedding them in the session.

```json
{
  "review_event": ["APPROVE", "COMMENT"],
  "forbid": ["REQUEST_CHANGES"],
  "stack": { "base": "<head_branch>", "push_to_reviewed_branch": false }
}
```

## What the session does with it

- `order.json` → the quickfix walk (`<Leader>ro`).
- Markers → curated by hand, then harvested to `.review/findings.md`
  (`<Leader>rw`), which is the input to implementation.
- `fix` and plain findings → implemented in the stack worktree, one commit per
  finding, message `REVIEW[<id>]: <text>`. The commit is the acceptance and the
  grouping.
- `ask` findings → the review comment body.
- `note` → dropped.

The authority for what the review *contains* is always
`git diff <pr_head>..HEAD` in the stack worktree. The commit log is an
incremental history, not a manifest: changes can be taken back out.
