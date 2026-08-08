---
name: keystroke-review
description: Periodic review of the nvim keystroke log -- find the editing habit worth changing and set the next drills
user-invocable: true
---

Review the nvim keystroke log and set the next drills.

$ARGUMENTS

## What this is

`nvim/lua/keylog.lua` records every normal/visual/operator-pending key. The Dojo
(`nvim/lua/plugins/dojo.lua`, `<Leader>?`) reads a small summary of that log and
opens on the drills it names. This skill is the step between the two: read the
raw log, find the one habit that costs the most, and write the summary.

The output is a short spoken report plus one file:
`~/.local/state/nvim/keylog/review.json`. Nothing else is required. Editing the
Dojo's entry table is optional and separate — see the last section.

This is not a leaderboard and not a config session. One finding that changes how
a day is spent beats ten observations.

## Cadence

Weekly-ish. The log keeps 60 days (`RETENTION_DAYS` in `keylog.lua`), so a gap
longer than that silently drops evidence. A window with fewer than a couple of
thousand keys cannot support a subtle claim — say so rather than reaching.

## 1. Run the report

```
python3 ~/.claude/skills/keystroke-review/report.py --review
```

It reads the log, the previous `review.json`, and the Dojo's entry table, then
prints three windows (before the last review, since it, and everything retained)
and a per-entry usage table. `--review` rewrites `review.json` with fresh counts
and an **empty** drills list, which step 4 fills in. Add `--since YYYY-MM-DD` to
override the split; the default is the day after the previous review.

Counting is the script's job. Everything below is yours.

## 2. Read it honestly

The log has sharp edges. Getting these wrong produces a confident wrong finding:

- **Insert mode is not recorded at all.** The `edit` class therefore undercounts
  editing by design. Never conclude "you barely edit".
- **Key records exclude mapping expansion; command records do not.** `vim.on_key`
  drops keys with no `typed` value, but `CmdlineLeave` fires for commands a
  mapping ran. A `:call` count is a plugin's own glue firing (NERDTree's `o`
  runs one per node), not something typed. Discount those.
- **A run at ≤120ms median gap is one key held down**, not N decisions. The
  report separates these. The distance travelled is still real — the decision
  count is not.
- **`ft` is whichever buffer the key landed in**, so `nerdtree`, `fzf`, `qf` and
  `DiffviewFiles` appear as filetypes. Keys there are UI navigation rather than
  code navigation, and telling those two apart is often where the finding is.
  `?` means no filetype — scratch buffers, dashboards, a fresh `:new`.
- **A binding added mid-window has had less time to be pressed.** Before calling
  one unused, `git log -- <file>` for when it landed, and count from there.
- **Raw counts across unequal windows mean nothing.** Use the per-1000 rates the
  report prints.
- **Retention prunes silently.** The oldest date in the report is not necessarily
  when logging started.

## 3. Find the finding

Ask, in this order, and stop at the first one with a number behind it:

1. **Where does vertical movement go?** It is normally the largest class by far.
   The question is never "is j/k high" — it always is — but *which buffer* it is
   spent in, because that names the replacement. j/k inside a source file wants
   a structural motion or a symbol picker; j/k inside a file tree wants a fuzzy
   file picker; j/k inside a picker wants a better query.
2. **What is the ratio of scrolling to targeting?** Vertical vs `search` +
   `targeted`. A large ratio means files are being read top-down rather than
   navigated, and `/` is the cheapest fix available.
3. **Which bound thing is never pressed, and does it cover a filetype that is
   soaking up movement?** An unused binding is only interesting when the work it
   would serve is demonstrably happening.
4. **What is pressed often but not in the Dojo?** The report's key list against
   the entry table shows this. It is either a habit worth documenting or one
   worth replacing.
5. **Did the previous drills move?** Compare their rates across the two windows.
   Say plainly when they did not — an unmoved drill is the most useful signal in
   the file.

## 4. Set the drills

At most **three**. The Dojo opens on them, and a list nobody can hold in their
head is not a list of drills.

Each drill is `{keys, note}` where:

- `keys` is **one** key sequence, exactly as the Dojo would write it. The Dojo
  feeds it verbatim on Enter, so `"¨f  åf"` would be typed as literal text —
  name one half and mention the other in the note.
- `keys` names the **replacement**, not the habit being dropped. A drill you
  cannot press is a complaint.
- `note` is one line carrying the number that justifies it. "Never pressed" on
  its own says nothing about whether it should have been. The Dojo renders it on
  a single row after a ~35-column prefix, so keep it under about 90 characters.

Retire a drill when it stopped earning its place — either it moved, or it did
not move and the evidence behind it has thinned. Carrying an unmoved drill
forward is fine once, with the note updated to say it did not move.

Then write them into the `drills` array the script left empty:

```json
"drills": [
  { "keys": "<C-p>", "note": "The tree took 561 keys, 389 of them j/k. <C-p> got 14. Open by name." }
]
```

## 5. Report back

Lead with the headline finding and its number. Then: what the previous drills
did, the new drills, and anything about the tooling itself that the run exposed
(a logger blind spot, a Dojo entry that misfires). Keep the tables out of the
reply unless asked — the numbers that matter are the ones in the drills.

## Editing the Dojo (optional, and only when asked)

`nvim/lua/plugins/dojo.lua` is hand-tended. Its own header states the rules;
follow them rather than this file:

- Entries are described by *when to reach for it*, not what it does.
- `added` is the date the row appeared. Set it when you add a row. **Never
  backdate it** — the age column is what makes "still unused after four months"
  readable.
- Prune as freely as you add.
- `run = false` marks a row the Dojo must not fire (a motion needing a target, a
  key meaningful only inside a picker).

Dojo edits are Nix-managed lua: they need a `home-manager switch` and a fresh
nvim before they take effect. `review.json` is not — it is read from disk on
every `<Leader>?`, so a new review shows up in the session already open.
