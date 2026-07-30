---
name: pr-session
description: Drive an AI-assisted local PR review — analyse a PR into in-code markers, implement the accepted findings as a stacked suggestion branch, then assemble the review locally. Runs inside a review session created by the `review <pr>` shell function.
user-invocable: true
disable-model-invocation: true
---

Run one phase of a local review session. `$ARGUMENTS` selects it:

| `$ARGUMENTS` | Phase |
|---|---|
| *(empty)* or `analyse` | **A** — analyse the PR into markers |
| `analyse --analysis <skill>` | **A**, delegated to a domain provider |
| `implement [ids]` | **B** — implement accepted findings on the stack |
| `assemble` | **C** — build the review artifacts locally |
| `publish` | **D** — send what `assemble` produced |
| `help [question]` | **Diagnose** — read-only; where this session stands and what to do next |

$ARGUMENTS

## Always

- **Read `.review/session.json` first.** No session file means you are not in a
  review worktree — stop and say so.
- **Never commit on the stack branch.** A commit is the reviewer's acceptance,
  made from the editor with `:ReviewAccept`. Yours to prepare, theirs to take.
- **Never push, never call `gh` to write, never touch the reviewed branch.**
- **Never tear a session down** — no `git worktree remove`, no branch deletion. Ending a
  session is `review retire <pr>`, and it is the reviewer's to run.
- The reviewer's uncommitted non-marker edits are theirs. In the review worktree
  ignore them entirely; in the stack worktree read them as instructions (Phase B).

---

## Phase A — analyse

Read `CONTRACT.md` before writing anything; it binds you.

Analysis comes in two forms and they converge: **something produces a finding set,
then this skill renders it.** Rendering is always yours — a provider returns findings
and performs no effects, so the marker writing, the id allocation and the `.review/`
files happen here on both paths, once.

**Where the findings come from.**

- *Delegated* — `--analysis <skill>` given: invoke that skill for this PR and point
  it at `CONTRACT.md` beside this file for the output shape. It returns the finding
  set; do not also run the built-in analysis. Verify what came back before rendering
  it: `order` has an entry per changed file, every finding has a `kind`, a `text` and
  at least one site whose file is real, and `summary` is present. Report a breach
  rather than quietly repairing it.
- *Built-in* — nothing given: derive them yourself, per **Built-in form** below.

**Then render, identically either way:**

1. **Allocate ids** from `max(existing) + 1`, scanning the whole worktree — ids are
   unique across it, and gaps are normal.
2. **Write the markers.** One line per site, in that file's own comment syntax,
   directly above the code concerned and at its indentation. The finding's first site
   carries the body; the rest are bare `REVIEW[<id>]` back-references.
3. **Write `.review/order.json`, `summary.md`, and `policy.json`** if a policy came
   back. `order.json` and `summary.md` are derived, so rewrite them **whole** — an
   order that shrinks to this run's findings hides the rest of the change.
4. `nvim --server <review_socket> --remote-send '<Cmd>checktime<CR>'`, or the markers
   stay invisible in an open buffer.
5. **Report** the count by kind, and that `<Leader>ro` walks the order.

**If markers already exist, this is a re-run.** The reviewer has curated them since —
some deleted on purpose, some reworded, some retagged. So collect what is already
there and pass it to the analysis as covered ground; render only findings none of
them covers, never restate one the reviewer deleted, and never renumber. Say what was
already there and what you added.

**Built-in form.** Deliberately small — a starting point for the reviewer, not a
verdict. It produces the same finding set a provider would; rendering it is the
shared step above.

1. `git diff <merge_base>...<pr_head>` — commits, never the working tree.
2. Read the changed files at the PR head for context the diff omits. Where a
   change leans on a caller or an invariant elsewhere, read that too.
3. Decide the **review order**: which file makes the rest legible, and why. State
   the reason in terms of what reading it first prevents — "the handler decides
   which path the rest takes", not "it is the main file". Every changed file gets an
   entry — it is the route through the whole PR, not a list of the places you
   commented.
4. Find the findings, each with the sites it occurs at. Look for: behaviour that does
   not match what the PR claims; unhandled empty, duplicate or boundary inputs;
   errors swallowed or left in a partial state; work that grows with data; and new
   behaviour with no test covering its failure mode. Say what is wrong and why it
   matters — never restate the code.
5. Write the summary prose (below).

### `summary.md`

Markers say what is wrong at a site. This says what the change *is* — the reasoning,
the background and the implications — and it has to stand on its own as text, read
away from the code by someone who has not opened the diff.

Structured answer-first, so the first paragraph is the whole review and everything
after it is support:

```markdown
# <pr title> — review summary

## The short version

<2–4 sentences. The single most important judgement about this change. If a reader
stops here, they have the review.>

## <a theme, named for the problem>

<2–5 sentences: what the pattern is, why it matters, what follows if it stays.>

## <a second theme>

## Where to start

<1–3 ordered bullets.>
```

Hard rules, because this is prose that earns its place or does not exist:

- **500 words, and 2–4 themes.** Group by reason, never by file — two findings sharing
  a cause are one theme.
- **No code, no file paths, no line numbers, no identifiers.** Those are what the
  markers and the diff are for. A sentence that needs a symbol name to make sense
  belongs in a marker instead.
- **Never narrate the diff.** "Adds a flag and a lookup table" is a translation of
  code into English and is worth nothing. Write what the change assumes, what it
  breaks, what it makes harder next time.
- Rewritten whole on a re-run, like `order.json`. On a clean diff, write the short
  version alone and stop.

`<Leader>rw` embeds it at the top of `findings.md`, which is where the reviewer reads
it — so it introduces the findings rather than duplicating them.

**Do not build, typecheck or run tests in this phase.** Analysis is reading. A
worktree may lack a dependency tree or a toolchain, and chasing that spends time
and tokens for nothing — note the gap in your report and move on. Verification
belongs to Phase B, where there is an actual change to verify.

**Restraint is the point.** A marker the reviewer deletes cost them more than a
finding you never wrote. Prefer few, specific, load-bearing findings. If the diff
is clean, say so and write no markers — an empty analysis is a valid result.

---

## Phase B — implement

Input is `.review/findings.md`, written by the reviewer with `<Leader>rw`. Its
absence means they have not finished curating — stop and say so.

1. Read `findings.md` and `session.json`.
2. Determine what is already landed:
   `git log --format=%s <pr_head>..HEAD` in the stack worktree, matching
   `REVIEW[<id>]`. Skip those. **Then confirm against
   `git diff <pr_head>..HEAD`** — a finding whose commit was later dropped is not
   landed, and the diff is the authority.
3. Pick the next unlanded `fix` or plain finding, or the ids named in
   `$ARGUMENTS`. **One at a time unless told otherwise** — the reviewer reads
   each before accepting, and a pile of simultaneous changes cannot be read.
4. **Check for a demonstration first.** Uncommitted changes in the stack worktree
   are the reviewer showing you what they mean. Read `git diff` there and treat
   it as the instruction: finish it, apply it consistently, keep their shape.
   Never revert or rewrite it wholesale.
5. Implement in the **stack worktree**, leaving the change **uncommitted**.
   Run the repo's tests if a change is more than cosmetic.
6. Report: what changed, in which files, and that `<Leader>hs` accepts hunks and
   `:ReviewAccept <id>` takes it into the review.

`ask` findings are never implemented. If implementing a finding shows it was
wrong, say so and leave the tree clean rather than shipping a half-fix.

---

## Phase C — assemble

Writes files and stops. Nothing leaves the machine until `publish` is invoked
separately.

**Preconditions.** Stop and report if either fails:

- The stack worktree is clean (`git status --porcelain` empty). Uncommitted work
  means something is still in flight.
- Every non-`note` finding is either landed or `ask`.

**Assemble** into the **review worktree's** `.review/out/` — the session's `.review/`
is the one beside the markers, so every artifact for a session lives in one place:

| File | Contents |
|---|---|
| `pr-body.md` | Title and body for the stacked PR. Ends with the handover (below). |
| `review-body.md` | The review comment: 2–4 lines of what you found, the `ask` questions, and a link to the stack. Ends with the handover (below). |
| `plan.sh` | The literal commands `publish` will run, in order, with no logic. |

**The handover.** Both bodies close by transferring ownership: the stack branch and
its PR are the author's, with full write access, to rebase, amend, squash or extend.
Say it as a transfer, not a verdict on the findings.

Two things not to write, because both are claims you cannot support:

- **Never characterise the suggestions as optional or non-blocking as a class** — not
  "none blocking", not "nothing here needs to merge". Whether a finding must land is
  the author's and the reviewer's judgement, per finding, and pre-emptively waiving it
  turns real findings into noise.
- **Never invite the author to open their own PR** for this work. It already exists;
  the point of the handover is that they take this one over rather than redo it.

State severity per finding where you have grounds, and otherwise not at all.

Honour `.review/policy.json` if present — its `forbid` list is absolute.
Absent a policy, the review event is `--comment`, never `--request-changes`.

Then tell the reviewer to read `out/` and
`DiffviewOpen <pr_head>...HEAD` in the stack worktree.

---

## Phase D — publish

Runs `plan.sh` and nothing else — no regeneration, so what was read is what is sent.
Report each command's result. If a PR for this stack branch already exists, update it
rather than opening a second.

---

## help

Read-only. Diagnose the session and say what to do next; change nothing, and never
"repair" what you find. If `$ARGUMENTS` carries a question, answer that specifically
rather than reciting the whole state.

Gather, then compare:

1. `session.json` — role, `pr_head`, `pr_tip`, both worktree paths.
2. `git rev-parse HEAD` in **each** worktree, and `git status --porcelain` in each.
3. Markers in the review worktree, and whether `findings.md` is older than the newest
   marker edit.
4. `git log --format=%s <pr_head>..HEAD` in the stack worktree, checked against
   `git diff <pr_head>..HEAD` — the diff is the authority.
5. Which of `order.json`, `findings.md`, `out/` exist.

Report **where the session stands**, then the **single next action**, then any
**desync** you found, naming the specific one:

- The session's `pr_head` differs from `pr_tip` — the PR moved upstream and this
  session still reviews the older commit, deliberately.
- A worktree's `HEAD` differs from the session's `pr_head` — the session file and the
  checkout disagree; every computed range is suspect.
- `findings.md` predates the markers — Phase B would act on a stale set.
- A commit names a finding the diff no longer contains, or vice versa.
- Markers exist in the stack worktree — they must not; that tree is code only.

If nothing is wrong, say so plainly and give the next action anyway. A reviewer asking
this is usually asking "what now", and answering only "all clear" wastes the question.

A session can also be **finished**: the reviewed PR has merged or closed and nothing is
left in flight. Then the next action is `review retire <pr>`, which archives the findings
and the stack before removing the worktrees. Say so — and do not run it.
