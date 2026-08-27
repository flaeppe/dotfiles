---
name: challenge
description: Before any code is written — plan the work, have the approach challenged by simplicity-expert, and fold the result in before the plan file is written. Operates on a plan, not a diff.
user-invocable: true
disable-model-invocation: true
---

The work to plan:

$ARGUMENTS

Draft, challenge, merge, persist — in that order.

1. **Draft with `planning`.** Load the `planning` skill and run its
   decomposition to a draft, in the conversation. Nothing on disk yet.
   `planning` stays standalone and unmodified; you only call it. If the work
   does not warrant a plan file, say so and stop — do not dispatch.

2. **Dispatch one agent.** Agent tool, `subagent_type: simplicity-expert`.
   Give it the draft plan verbatim, the absolute repo path, and "return only
   your output contract". One agent, not a fan-out. Wait for it.

3. **Merge before persisting.** The simplest-thing line and every alternate
   get exactly one disposition:
   - **adopted** — the plan body changes to match;
   - **rejected** — one line of why, in the plan;
   - **noted** — carried as an alternative worth remembering.

   `KEEP` is a constraint, not a proposal — honour it, or record the override.
   Fold adopted items into the plan body. Record the rest under one
   `## Alternatives considered` section, one line each — *approach —
   trade-off — why not* — so a later session does not re-propose them.

   **Gate:** state every disposition in the conversation before writing, and
   do not persist until the simplest-thing line is answered — adopted, or
   rejected with a reason. An ENDORSE satisfies it.

4. **Persist per `planning`'s File Conventions** — location, shape, `NNN`,
   header. Those rules live there and are not restated here. Report the path.
