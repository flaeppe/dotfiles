---
name: skill-improver
description: At session end or on demand, refine the skill(s) exercised this session — close gaps, ambiguity, missing steps, inefficiency — within no-rehaul bounds. Human-gated; proposes a diff, never writes unprompted. Biases hard toward proposing nothing.
user-invocable: true
disable-model-invocation: true
---

Refine the skill(s) exercised in THIS session. You propose; the human decides.
**Nothing is written until approved.** Bias hard toward proposing *nothing* — a
skill that only ever grows rots; most sessions should end in "no change".

$ARGUMENTS

## 1. Identify the target skill

From this session, find which skill(s) were actually invoked (the `Skill` tool
calls). Exclude yourself (`skill-improver`) — never improve yourself in the
same run. If several ran, take the one this session genuinely exercised, or ask
which. `$ARGUMENTS` may name it directly.

## 2. Understand it fully (this is the objectivity anchor)

`Read` the **entire** skill — SKILL.md **and every** leaf it bundles (the
on-demand files under `references/` or `leaves/`, nested included), not only the
paths this session touched — plus its `SPEC.md` and `README.md` if
present. You
judge every candidate change against the skill's whole purpose and its spec.
**The session is evidence of a possible gap; it is not the definition of the
fix.** You have no memory of past sessions — so do not let this one session
speak for all of them.

## 3. Find friction

Where did the skill mislead, stall, under-specify, waste steps, or omit
something the session needed? List candidates, one line each. Resist inventing
work: if the skill performed fine, say so and stop.

## 4. Gate every candidate — it must pass ALL, or drop it (or downgrade to a note)

1. **Generality** — would this help across sessions, or is it overfit to this
   session's specifics (one PR, file, name, or quirk)? Overfit → drop.
2. **Spec** — respects the purpose, invariants, and scope in `SPEC.md`.
   Violates an invariant → drop. **No spec present → you may make only
   net-neutral-or-smaller edits** (a skill with no declared budget has not
   earned room to grow) — met by reshaping your own change, never by deleting
   unrelated content to fund it. If it only fits by cutting something that was
   pulling its weight, propose a minimal `SPEC.md` instead and let the human
   grant the room deliberately.
3. **No rehaul** — if the change would cross the spec's rehaul threshold
   (absent a spec: >25% of SKILL.md lines, or the frontmatter
   description/scope, or the structure), **do nothing for it**. Say so and
   recommend a separate rewrite session or a new sibling skill. This skill
   refines; it does not replace.

**Size is NOT a gate — measure it, report it, never let it filter.** The gates
above judge whether a change is *right and in scope*; budget is about *room*,
which is the human's call, not the skill's. Generate the cleanest proposal on
merit with the budget ignored — never pre-shrink a proposal and never drop one
for "no room". Then run `measure.sh` and report worst-path before/after with the
proposal (delta, and over/under the spec's budget), noting any offsets you
see. The human decides how to fit it: rephrase, trim, or raise the budget.

Prefer the **narrowest** edit that fixes it, and narrowest is about *shape*
before size: repair the lines that are wrong before adding lines that argue with
them. If your diagnosis names specific text, your diff should touch that text —
a new rule restating one that already exists elsewhere is a patch, not a fix, and
it leaves the contradiction in place for the next run to trip over. Also prefer
editing a leaf over the router — a change to SKILL.md affects every path; a leaf
change is contained.

## 5. Propose — never apply unprompted

Present each surviving change as a diff + one line of why, and the
`measure.sh` before/after. On explicit approval, apply to the working files.
Do not commit.

A change rarely lives in SKILL.md alone: when it alters behaviour, structure, or
budget, reconcile the sibling docs in the **same** proposal — the README's
concept map and the SPEC's invariants / budget / design-intent — and capture the
*why*, so a later session doesn't undo it. A SKILL-only diff that leaves README
or SPEC stale is an incomplete change, not a done one.

If nothing survives the gates, say "no change" in one line — that
is the expected, healthy outcome — then **still do step 6**: expansion is
independent of refinement (a session can need no text change yet surface a new
leaf, or need to confirm none).

## 6. Structural candidates — flag new branches, never author them

Refining existing text is step 5's job and stays conservative. Growing a skill's
*tree* (the leaves the router loads on demand) is deliberate authoring — the
human's job — so here you **flag** a new-leaf candidate, you never write one.
Flagging is cheap (it changes nothing; the human decides), so flag more readily
than you would mutate — but keep it clean: one well-evidenced candidate beats
five speculative ones.

Flag a candidate only when all hold this session:
- **Uncovered** — the work hit an input category no existing leaf covers and the
  router handles only shallowly (the operator reasoned the whole area from
  scratch).
- **Generalizable** — a recurring *category*, not this item's quirk.
- **Depth-worthy** — enough specific substance that one more line in the router
  (or a row in the routing manifest, if the skill routes leaves mechanically)
  won't do; it wants its own checklist.

Output one line per candidate — `leaf candidate: <name> — <category it covers>;
evidence: <what had to be derived from scratch>`. **Run this scan every round and
always emit a verdict** — the candidate line(s), or `no new-leaf candidate this
round` when none — so expansion is attempted and auditable each time, not skipped
on a quiet session. Dedupe against existing leaves; don't restate one already
declined. The human aggregates these across sessions and authors the leaf once
the category recurs.

## Notes

- **Stateless by design.** This keeps no change log; it judges only the current
  session against the skill + spec. When you want history, track the skill
  in git and read `git log` — don't build a journal file.
- A spec is a few lines that **complement** the skill, never restate it:
  purpose, design intent, invariants, size budget (chars), rehaul threshold —
  the context wanted only when scrutinising the skill, not at runtime. Copying
  the skill's operational content in just bloats it. If the target skill lacks a
  spec and clearly warrants governed growth, propose creating a minimal
  `SPEC.md` as its own reviewed change — don't silently grow an ungoverned
  skill.
