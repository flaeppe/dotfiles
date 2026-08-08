# The `.review/` contract

The boundary between a **provider** (whatever analyses a PR) and the **session**
(the editor tooling that curates, implements and ships). Either side can be
replaced without the other knowing, as long as this holds.

This file is self-contained: a provider can be pointed at it alone.

## What a provider is

A **function**: a pull request goes in, a finding set comes out. Nothing else.

It writes no files, touches no git state, and calls nothing that posts. Not because
it is forbidden to — because producing the finding set *is* the whole job, and the
session performs every effect. A provider therefore needs to know nothing about
worktrees, editors, suggestion stacks or how a review gets posted, and cannot break
any of them.

That also keeps conformance cheap, which is the point: returning one JSON document
is a far lower bar than placing markers at the right indentation in each language's
comment syntax with ids allocated across a whole worktree. Those are mechanics, and
mechanics belong in one place instead of in every provider.

## Input

| | |
|---|---|
| `repo` | the repository under review |
| `base`, `head` | the commits to diff: `git diff <base>...<head>` |
| `covered` | optional — findings the reviewer already holds, on a re-run |

Read the diff **from those commits, never from the working tree**. The tree may be
dirty with markers and the reviewer's scratch edits at any time, so reading it makes
analysis unrepeatable mid-session.

`covered` is how a re-run avoids fighting a curated set. A finding already in it is
not returned again — and one the reviewer *deleted* is absent from it, so proposing
it again means proposing something they rejected.

## Output

One JSON document, as the provider's return value.

```json
{
  "order": [
    { "file": "src/handler.go", "line": 42,
      "why": "entry point — decides which path the rest of the diff takes" },
    { "file": "src/domain/fixtures.go", "context": true,
      "why": "not in this PR — where the capability the diff works around would live" }
  ],
  "findings": [
    { "kind": "fix",
      "text": "the post-insert UPDATE works around a missing seed capability; the field already exists, so create the record in the target state instead",
      "sites": [ { "file": "src/scripts/dev/link.ts", "line": 131 },
                 { "file": "src/domain/fixtures.go", "line": 338 } ] }
  ],
  "summary": "# … markdown …",
  "policy": { "review_event": ["APPROVE", "COMMENT"],
              "forbid": ["REQUEST_CHANGES"] }
}
```

### `order` — required

The route through the change, **one entry per changed file**, including files the
provider found nothing in. This is the reviewer's reading order, not an index of
findings: a file with no comment still has to be read, and its absence silently
shrinks the PR. Say so in `why` when there is nothing there — "no findings; read to
confirm the rename is mechanical".

`why` becomes the reviewer's list text, so write what reading that file *first*
prevents. `line` defaults to 1. A file outside the diff may appear only with
`"context": true`; unmarked, it misrepresents how large the change is.

### `findings` — required, may be empty

An empty list is a valid result. A finding the reviewer deletes cost them more than
one that was never written.

| Field | |
|---|---|
| `kind` | `fix` · `finding` · `ask` · `note` |
| `text` | what is wrong and why it matters — never a restatement of the code |
| `sites` | one or more `{ file, line }`; the first is where the text belongs |

**No ids.** The session allocates them, because uniqueness is a property of the whole
worktree and of markers already in it, not of one analysis pass.

Kinds, chosen honestly:

- `fix` — the change is known and mechanical. A redesign is never `fix`: claiming it
  hands the session a half-fix to build.
- `finding` — real, but what to do about it needs judgment.
- `ask` — nothing to change until the author answers.
- `note` — private to the reviewer; never reported.

One finding at several places is **one entry with several sites**, never several
entries. That is what turns "wrong in six places" into one finding.

### `summary` — required

The review as standalone prose, to be read away from the code by someone who has not
opened the diff. Answer first: the opening block is the whole review and everything
after it is support. At most 500 words, 2–4 themes grouped by cause rather than by
file, and no code, paths, line numbers or identifiers — a sentence that needs a
symbol name belongs in a finding. Never narrate the diff; write what the change
assumes, what it breaks, and what it makes harder next time.

### `policy` — optional

House rules constraining how the review may be posted. Declared as data because
executing them is the session's job, not the provider's.

## What the session does with it

Every effect happens here:

1. Allocate ids from `max(existing) + 1`.
2. Render each finding as markers — the first site carries the body, the rest are
   bare back-references — one line each, in the file's own comment syntax, directly
   above the code concerned and at its indentation:

   ```
   REVIEW[3]: this belongs in the domain layer     a finding
   REVIEW[3]fix: extract to the domain layer       becomes code on the stack
   REVIEW[3]ask: why is the retry unbounded?       a question for the author
   REVIEW[3]note: check the sibling flow           private; never reported
   REVIEW[3]                                       another site for finding 3
   ```

3. Write `order.json`, `summary.md` and, if given, `policy.json` into the review
   worktree's `.review/`, then refresh the editor so the markers appear.
4. Then: the reviewer curates; `findings.md` is harvested from the surviving markers;
   `fix` and plain findings become one commit each on the suggestion stack; `ask`
   findings become the review body; `note` is dropped.

Markers are never committed. The authority for what the review *contains* is always
`git diff <pr_head>..HEAD` in the stack worktree — the commit log is an incremental
history, not a manifest.

## `.review/`

| File | Written by | Contents |
|---|---|---|
| `session.json` | `review <pr>` | PR, role, pinned commits, stack branch, socket paths |
| `order.json` | the session, from `order` | the route through the PR |
| `summary.md` | the session, from `summary` | the review as prose |
| `policy.json` | the session, from `policy` | constraints the assembled review honours |
| `findings.md` | the editor | the harvested marker set, `note` excluded |
| `messages/<id>.md` | the session, while implementing | that suggestion commit's message: what it achieves, what was ruled out, what was verified |
| `out/` | `assemble` | the review artifacts, local until `publish` |

`messages/` is internal: the editor commits the file when the reviewer accepts that
finding, so the reasoning travels with the code. A provider neither reads nor writes it.
