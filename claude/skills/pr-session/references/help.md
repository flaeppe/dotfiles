# help — diagnose the session

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
- A landed finding's commit has no body and no `messages/<id>.md` — its reasoning was
  never recorded and cannot be recovered, so `assemble` will have to say so.
- An unlanded finding has a `messages/<id>.md` older than the stack's uncommitted work —
  the message describes something other than what is there to accept.

If nothing is wrong, say so plainly and give the next action anyway. A reviewer asking
this is usually asking "what now", and answering only "all clear" wastes the question.

A session can also be **finished**: the reviewed PR has merged or closed and nothing is
left in flight. Then the next action is `review retire <pr>`, which archives the findings
and the stack before removing the worktrees. Say so — and do not run it.
