---
name: pr
description: Create a pull request with well-structured title and description
user-invocable: true
---
Push the branch, then read EVERY commit on it — not just the latest — before
writing anything.

## Title

A PR title is a commit subject. Invoke the `commit` skill and follow it: same
conventional format, same type list, same why-not-what. Those rules are not
repeated here.

## Description

Three things, in this order, and nothing else:

1. **What changed** — a sentence or two. If the diff says it, don't repeat it.
2. **Why it had to change** — with evidence: a `file:line`, the error string, a
   count. Quote the error, don't describe it.
3. **The one thing a reviewer should push back on** — the risky call, the
   assumption you'd defend. If there honestly isn't one, write nothing.

**Hard ceiling: 10 lines, and the body must be SMALLER THAN THE DIFF.** Not a
default, not a target — a gate. Length tracks the change, never how long the
work took.

Check it before `gh pr create`, and state both numbers when reporting the PR:

```sh
wc -l < body.md                        # must be <= 10
wc -c < body.md                        # must be < the diff's byte count
git diff origin/<base>...HEAD | wc -c
```

If either fails, cut. Do not justify the length. The commonest overrun is a body
that argues for the change — the diff plus one `file:line` already does that.

**A body larger than its own diff is the failure this gate exists to catch.**
Observed: a 58-line body on a `+58/-4` diff, carrying five headings, a
`## Testing` section and a "findings from building it" section — every one of
them already forbidden below. The rules were present; nothing checked them, so
add the check rather than re-reading the rules.

Two that hit it, both one file:

> Alert and check-dialog links built from `BOARD_URL` pointed at
> `/apps/eng-monitoring`, but the host mounts apps at `/apps/:team/:name` — every
> link 404'd. One-line constant fix: `/apps/dev/eng-monitoring`.
>
> Found by clicking an alert link from the first production rollout.

> Two pushes to master 30 seconds apart ran concurrent deploys whose applies
> interleaved. Production ended on the **older** commit — `adefc14` applied
> 07:57:51Z, beating `30e6431` at 07:57:46Z.
>
> **Push back on `cancel-in-progress: false`** — it does not fix the false
> `rolled_out=success`, which lives elsewhere.

### Never write

- **That tests, lint, typecheck or CI ran or passed — and no section for it.**
  `## Test plan`, `## Testing`, `## Verification`, `- [x] tests pass`: all go,
  including the ones carrying real counts. The checks report themselves on the
  PR, so saying it is bloat when true and a lie before they finish.
- **A heading over a one-line section.** Headings earn their place only when two
  or more real sections survive; most PRs are prose with no headings at all.
- **A file-by-file walk of the diff.**
- **The journey, or the brief restated.** Only the landed approach exists, and
  ruling out an alternative is a clause, not a section.
- **`## Summary` as an opener.** The body IS the summary. A heading that labels
  the body costs a line and says nothing.
- **What you learned while building it.** Real findings go to `me note` or the
  plan file, where they outlive the PR — not the description, where they double
  its length and reach only whoever reviews this diff. This is the pressure that
  produces long bodies: the work felt substantial and the body is the nearest
  place to say so. Put it somewhere it lasts instead.
- **A section arguing the change is safe** — "what this is not", "why this is
  not a fallback". If a reviewer could misread the diff that way, one clause
  prevents it; a heading invites the argument.

Breaking changes and migration steps are content, not a section: put them in the
first two sentences. A table beats six one-line bullets.

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

    gh pr create --title "type(scope): subject" --body "$(cat <<'BODY'
    ...
    BODY
    )"

$ARGUMENTS
