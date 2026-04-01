---
description: Explore a codebase to map and understand a system before planning work
subtask: true
---
$ARGUMENTS Explore the codebase systematically to answer this. As you search,
map out what you find — trace call chains, data flows, integration points, and
boundaries between components. Identify key files, interfaces, and assumptions
the current implementation relies on. Note friction points, coupling, and
anything that would complicate changes.

While exploring:
- Summarize findings as you go rather than at the end. Build the picture
  incrementally.
- Use diagrams (mermaid) when they clarify relationships between components,
  services, or data flows. Don't force them where prose is clearer.
- Regularly check: am I still answering the original question or have I drifted
  into tangential code? Refocus if so.
- If you hit diminishing returns, or the answer depends on context not in the
  code (business rules, external systems, team decisions), stop and say what you
  found, what you couldn't determine, and what additional context would help.

Summarize your findings in a way that supports planning work — what exists, how
it fits together, and what constraints a future implementation needs to respect.
