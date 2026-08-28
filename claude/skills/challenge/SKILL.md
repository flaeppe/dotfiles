---
name: challenge
description: Plan an approach with `planning`, have it challenged by simplicity-expert, then persist the version you pick. Input is a task, an existing plan, or a PR; output is always a plan file, never an edit.
user-invocable: true
disable-model-invocation: true
---

What to plan — a task, an existing plan file, or an implementation/PR:

$ARGUMENTS

Steps 1, 3 and 4 are yours. Step 2 is the agent's, and nothing else is.

1. **Draft with `planning`.** Load the `planning` skill and run its
   decomposition over whatever came in, to a draft in the conversation.
   Nothing on disk yet. `planning` stays standalone and unmodified; you only
   call it. If the work does not warrant a plan file, say so and stop — do
   not dispatch.

2. **Dispatch one agent.** Agent tool, `subagent_type: simplicity-expert`.
   Give it the draft plan verbatim, the absolute repo path, and "return only
   your output contract". One agent, not a fan-out; it reads and returns,
   writing nothing. Wait for it.

3. **Present both, decide neither.** Five blocks in the conversation, never
   interleaved:

   ```
   VERDICT    — the expert's one line, verbatim
   ORIGINAL   — the draft from step 1, one line per increment
   ALTERNATES — <approach> — trades <X> for <Y> — proposed: adopt|reject|note
                the simplest-thing line always sits here
   KEEP       — what the expert says must not change
   RULED OUT  — investigated and killed, with the evidence — never dropped
   ```

   Proposed dispositions are yours to suggest, never to apply. Fold nothing
   in, write nothing. **Stop here and wait for the call.**

4. **Persist what was chosen.** Fold the adopted items into the plan body.
   Record the rest under one `## Alternatives considered` section, one line
   each — *approach — trade-off — why not* — including every `RULED OUT`
   line, so a later session does not re-propose them. Then persist per
   `planning`'s **File Conventions** — location, shape, `NNN`, header. Those
   rules live there and are not restated here. Report the path.
