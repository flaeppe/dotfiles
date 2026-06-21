---
name: prompt
description: Distill a brain dump into a concise, copy-pasteable prompt for a coding agent
user-invocable: true
disable-model-invocation: true
---

Turn the brain dump below into a tight prompt I can paste into Claude Code.
You are producing a prompt, not having a conversation and not doing the work.

$ARGUMENTS

## What you're producing

A prompt for a coding agent — my own Claude Code, where my global CLAUDE.md is
already loaded. So:

- Carry only **task, load-bearing context, constraints, acceptance**.
- Never restate coding standards, conciseness, minimalism, or persona — those
  are already active in the target session. Repeating them is noise.
- Never invent requirements I didn't state. A gap is flagged, not filled.

## Method

1. **Find the one ask.** What single thing must this accomplish? Everything
   else is support. Two unrelated asks → say so and produce two prompts.
2. **Mark the emphasis.** What did I stress, repeat, or react to? That signal
   goes up front and carries weight.
3. **Keep load-bearing context only.** Context earns its place if the agent
   would do the wrong thing without it — a constraint, a gotcha, a prior
   decision, a specific file or system to touch. Background that doesn't change
   the work is noise; cut it.
4. **Make constraints and "done" explicit.** Surface implicit limits. Define
   observable success (a test passes, a behavior changes) when the dump implies
   one.
5. **Size to the task.** A one-line fix gets a one-line prompt. Don't pad to
   look thorough; don't compress a real spec into a tweet.

## Structure

Imperative goal first, then only the sections that carry weight:

```
<imperative one-line goal>

Context: <only what changes the work>
Constraints: <explicit limits, gotchas>
Done when: <observable acceptance>
Avoid: <trap the dump implies — omit if none>
```

Drop any empty section. Most prompts need the goal plus one or two others, not
all four.

## Output

The prompt in a code block, then a 2-3 line note:

- **Emphasis** — what you treated as the core ask, and why.
- **Cut** — what you dropped as non-load-bearing, so I can object.

If something genuinely blocking is missing — you cannot write a coherent prompt
without it — ask one tight question. Otherwise produce the prompt and state any
assumptions in the note.
