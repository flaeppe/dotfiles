---
name: pr
description: Write or edit a pull request's title and body. Use before gh pr create, gh pr edit, or "open a PR".
user-invocable: true
---
Push the branch, then read EVERY commit on it — not just the latest — before
writing anything.

## Title

A PR title is a commit subject. Invoke the `commit` skill and follow it: same
conventional format, same type list, same why-not-what. Those rules are not
repeated here.

## Description

Write for a reviewer who knows the codebase but not this corner of it. They read
top-down and stop once they know enough, so order decides what gets read:

1. **Summary** — two to four plain-English sentences: what changes and why it
   matters, in words someone new to the area follows. No `file:line`, no counts.
   A merge order, breaking change or migration step goes here.
2. **Context** — what the reader needs before the diff makes sense: how this
   part of the system behaves, what goes wrong today, why this approach.
3. **Evidence** — the `file:line`s, error strings, counts and timestamps behind
   the claims above. Quote the error, don't describe it. A table beats six
   one-line bullets.
4. **Push back on** — the risky call, the assumption you'd defend. If there
   honestly isn't one, write nothing.

Give each its `##` heading (`## Summary`, `## Context`, `## Evidence`,
`## Push back on`). A change the summary fully explains — a one-line fix — is
one paragraph plus the push-back line, no headings: a heading over one sentence
is noise.

**A normal PR is a two-to-three-minute read: 300-450 words is the ceiling, the
body stays smaller than the diff, and no paragraph runs past 80 words.** It is a
summary, not a report or a transcript. Length tracks the change, never how long
the work took. Check before creating:

```sh
wc -w < body.md                        # must be <= 450
wc -c < body.md                        # must be < the diff's byte count
git diff origin/<base>...HEAD | wc -c
```

Over budget, cut in this order: Evidence first — keep the one number or
`file:line` that decides each claim and move the rest (full tables,
derivations) to a PR comment, or drop it; then Context. Never the Summary or the
push-back line, and never by packing more into each line.

Two short ones, both one file:

> Alert and check-dialog links built from `BOARD_URL` pointed at
> `/apps/eng-monitoring`, but the host mounts apps at `/apps/:team/:name` — every
> link 404'd. One-line constant fix: `/apps/dev/eng-monitoring`.

> Two pushes to master 30 seconds apart ran concurrent deploys whose applies
> interleaved. Production ended on the **older** commit — `adefc14` applied
> 07:57:51Z, beating `30e6431` at 07:57:46Z.
>
> **Push back on `cancel-in-progress: false`** — it does not fix the false
> `rolled_out=success`, which lives elsewhere.

One that needs the headings:

> ## Summary
> When a large batch of events arrives, the worker takes far more messages than
> it has database connections, so most time out and are redelivered. This caps
> each pod at one message per connection; the rest wait in the queue.
>
> ## Context
> Each handler holds one connection at a time, so 20 connections serve 20
> handlers with no waiting. The queue redelivers what times out.
>
> ## Evidence
> | | before | after |
> |---|---|---|
> | messages held per pod | 1,000 | 20 |
> | deliveries per message, last burst | 10.8 | ~1 (expected) |
>
> ## Push back on
> Expecting speed: the database CPU at 99% bounds the drain, not this cap.

### Never write

- **Anything only this machine or this conversation can resolve.** A path
  outside the repo (`~/.plan/…`, `/Users/…`), a plan file's name or number
  ("per 041"), the tools and sessions that did the work (Sam, a subagent, me,
  af, kn, "this session", "the sandbox"), or who will merge. If the evidence
  lives in a plan file, state the fact and its number, not where it lives.
- **That tests, lint, typecheck or CI ran or passed — and no section for it.**
  `## Test plan`, `## Testing`, `## Verification`, `- [x] tests pass`: all go,
  including the ones carrying real counts. The checks report themselves on the
  PR, so saying it is bloat when true and a lie before they finish.
- **A file-by-file walk of the diff.**
- **The journey, or the brief restated.** Only the landed approach exists, and
  ruling out an alternative is a clause, not a section.
- **What you learned while building it.** Real findings go to `me note` or the
  plan file, where they outlive the PR — not the description, where they double
  its length and reach only whoever reviews this diff. This is the pressure that
  produces long bodies: the work felt substantial and the body is the nearest
  place to say so. Put it somewhere it lasts instead.
- **A section arguing the change is safe** — "what this is not", "why this is
  not a fallback". If a reviewer could misread the diff that way, one clause
  prevents it; a heading invites the argument.

## Plain language

A word that only means something to someone who has read this code cannot carry
a sentence a reviewer reads — in the title, the body, **or a UI string in the
diff**. Jargon shipped in the product is the worse half.

**Cite an identifier as an identifier; never conjugate it into English.**
`legBump()` and `GROUP BY` are fine in backticks. "fold the legs into one delta"
is not: leg, fold and delta are names from inside the code, used as if the
reviewer shares them.

Real corrections from this org:

| invented | plain |
|---|---|
| `refactor: fold legs into one delta per creditor` | `refactor: one update per creditor, not two` |
| `feat: show when the data walk is claimed` | `feat: show when the data can refresh again` |
| "The union exists because `DeltaBuilder` kept two maps, `legBumps` and `legNames`" | "The union is only there because the two lists arrive separately" |
| "`legBump()` and `legName()` keep their signatures, so no ingest lane changes" | "The two functions that record the news keep their signatures, so nothing calling them changed" |
| `data walk claimed · frees in 4m` — a UI label | `can refresh in 4m` |

The test: read it to someone who has not opened the diff. If a noun makes them
ask "what's a leg?", replace the noun — not the sentence.

## Create it

Body's last line, always: `<!-- pr:v1 -->`. A hook checks for it and blocks
the create/edit without it — invisible in the rendered PR, so it costs
nothing.

    gh pr create --title "type(scope): subject" --body "$(cat <<'BODY'
    ...
    <!-- pr:v1 -->
    BODY
    )"

$ARGUMENTS
