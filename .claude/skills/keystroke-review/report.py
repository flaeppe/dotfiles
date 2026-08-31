#!/usr/bin/env python3
"""Aggregate the nvim keystroke log into the numbers a periodic review reads.

Counting only. Every judgement call -- which habit is worth a drill, whether a
binding should be pruned -- belongs to the reviewer, not to this file.
"""

from __future__ import annotations

import argparse
import collections
import datetime
import glob
import json
import os
import pathlib
import re
import sys
from collections.abc import Sequence
from typing import Any, Final

# One line of the keystroke log, as written.
Record = dict[str, Any]

# (date, that day's records), one entry per session file.
Sessions = list[tuple[str, list[Record]]]

KEYLOG: Final = os.path.expanduser("~/.local/state/nvim/keylog")
# <repo>/.claude/skills/keystroke-review/report.py, so the dotfiles root is four
# levels up. Derived rather than hardcoded: the repo is not checked out at the
# same path on every machine.
DOJO: Final = pathlib.Path(__file__).resolve().parents[3] / "nvim/lua/plugins/dojo.lua"

# `keytrans` spells control keys with an upper-case letter; the Dojo writes them
# the way vim documents them. Same key, two spellings, so one has to be folded.
LEADER: Final = "<Space>"

# A run of one key at this median gap or below was the keyboard repeating, not a
# finger pressing. macOS repeats at ~84ms at the fastest setting.
REPEAT_MS: Final = 120
RUN_MIN: Final = 5

MOTION_CLASSES: Final = {
    "vertical": [
        "j",
        "k",
        "<Down>",
        "<Up>",
        "<C-D>",
        "<C-U>",
        "<C-F>",
        "<C-B>",
        "G",
        "gg",
    ],
    "search": ["/", "?", "n", "N", "*", "#"],
    "inline": ["f", "F", "t", "T", "0", "$", "^", "w", "b", "e", "W", "B", "%"],
    "targeted": ["<C-O>", "<C-I>", "gd", "grd", "grr", "<C-E>", "<C-P>"],
    "edit": ["o", "O", "i", "a", "c", "d", "x", "p", "u", "<C-R>"],
}

# The motion classes above describe a source buffer. Inside the file tree they
# say nothing -- w/b/e have no meaning there, and these are the keys j/k should
# be losing ground to. Spelled as `keytrans` writes them.
TREE_KEYS: Final = {
    "<C-J>": "next sibling",
    "<C-K>": "previous sibling",
    "J": "last child",
    "K": "first child",
    "p": "parent",
    "P": "root",
    "x": "close parent",
    "X": "close children",
    "u": "up a directory",
    "O": "open recursively",
    "/": "search the tree buffer",
}

# Consecutive vertical keys in one buffer, broken by any other key or a pause
# this long, are one journey. Their length is the question a raw j/k total
# cannot answer: a median of 3 is cursor adjustment, a tail of 300 is a symbol
# jump that never happened.
BURST_GAP_MS: Final = 3000
LONG_BURST: Final = 10
# The log records no cursor position, so a half-screen jump is priced at a flat
# line count -- enough that <C-D> does not read as one line. Log the window
# height alongside the key if the tail ever needs to be exact.
VERTICAL_LINES: Final = {"<C-D>": 20, "<C-U>": 20, "<C-F>": 40, "<C-B>": 40}
# Absolute jumps, not travel: they end a burst rather than lengthening one.
BURST_BREAKERS: Final = {"G", "gg"}


def shift_day(date: str, days: int) -> str:
    stamp = datetime.date.fromisoformat(date) + datetime.timedelta(days=days)
    return stamp.isoformat()


def day_after(date: str) -> str:
    return shift_day(date, 1)


def day_before(date: str) -> str:
    return shift_day(date, -1)


def dojo_entries(path: str | os.PathLike[str]) -> list[tuple[str, str, str, str]]:
    """[(group, keys, desc, added)] in the order the Dojo lists them."""
    src = open(path).read()
    table = src[src.index("local ENTRIES = {") : src.index("\n-- Written by")]
    pattern = (
        r'group\s*=\s*"([^"]+)"\s*,\s*keys\s*=\s*"([^"]+)"\s*,'
        r'\s*desc\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*added\s*=\s*"([^"]+)"'
    )
    return [
        (m.group(1), m.group(2), m.group(3), m.group(4))
        for m in re.finditer(pattern, table)
    ]


def keytrans_forms(written: str) -> list[str]:
    """A Dojo `keys` field -> the raw log spellings that count toward it.

    Two keys on one row ("¨f  åf") are one habit and count together.
    """
    forms = []
    for key in written.split():
        key = key.replace("<Leader>", LEADER)
        key = re.sub(r"<C-(\w)>", lambda m: "<C-%s>" % m.group(1).upper(), key)
        forms.append(key)
    return forms


def read_sessions(keylog: str) -> Sessions:
    """[(date, [record, ...])] -- one entry per session file, chronological."""
    out: Sessions = []
    for path in sorted(glob.glob(f"{keylog}/keys-*.jsonl")):
        stamp = re.search(r"keys-(\d{4}-\d{2}-\d{2})", path)
        if not stamp:
            continue
        date = stamp.group(1)
        records: list[Record] = []
        for line in open(path):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                # A session killed mid-flush leaves one torn record. Skip it.
                pass
        if records:
            out.append((date, records))
    return out


class Window:
    """Everything counted over one date range."""

    label: str
    keys: collections.Counter[str]
    cmds: collections.Counter[str]
    by_filetype: collections.Counter[str]
    vertical_by_filetype: collections.Counter[str]
    keys_in_filetype: collections.defaultdict[str, collections.Counter[str]]
    # (key, length, median gap ms, filetype)
    runs: list[tuple[str, int, int, str]]
    # Lines travelled by each uninterrupted run of vertical keys, per filetype.
    bursts: collections.defaultdict[str, list[int]]
    dates: set[str]
    sessions: int
    cwds: collections.Counter[str]

    def __init__(self, sessions: Sessions, lo: str, hi: str, label: str) -> None:
        self.label = label
        self.keys = collections.Counter()
        self.cmds = collections.Counter()
        self.by_filetype = collections.Counter()
        self.vertical_by_filetype = collections.Counter()
        self.keys_in_filetype = collections.defaultdict(collections.Counter)
        self.runs = []
        self.bursts = collections.defaultdict(list)
        self.dates = set()
        self.sessions = 0
        self.cwds = collections.Counter()

        vertical = set(MOTION_CLASSES["vertical"])
        for date, records in sessions:
            if not (lo <= date <= hi):
                continue
            self.dates.add(date)
            self.sessions += 1
            self._scan(records, vertical)

    def _scan(self, records: list[Record], vertical: set[str]) -> None:
        filetype = ""
        cwd: str | None = None
        run_key: str | None = None
        run_times: list[int] = []
        run_filetype = ""
        burst_lines = 0
        burst_filetype = ""
        burst_last = 0
        for record in records:
            if "cwd" in record and "k" not in record:
                cwd = record["cwd"]
                continue
            filetype = record.get("ft", filetype) or "?"
            if cwd:
                self.cwds[cwd] += 1
            if "cmd" in record:
                self.cmds[record["cmd"]] += 1
                continue
            key = record.get("k")
            if key is None:
                continue
            self.keys[key] += 1
            self.by_filetype[filetype] += 1
            if key in vertical:
                self.vertical_by_filetype[filetype] += 1
            self.keys_in_filetype[filetype][key] += 1
            travelling = key in vertical and key not in BURST_BREAKERS
            broken = (
                filetype != burst_filetype or record["t"] - burst_last > BURST_GAP_MS
            )
            if not travelling or broken:
                self._close_burst(burst_lines, burst_filetype)
                burst_lines, burst_filetype = 0, filetype if travelling else ""
            if travelling:
                burst_lines += VERTICAL_LINES.get(key, 1)
                burst_last = record["t"]
            if key == run_key:
                run_times.append(record["t"])
            else:
                self._close_run(run_key, run_times, run_filetype)
                run_key, run_times, run_filetype = key, [record["t"]], filetype
        self._close_run(run_key, run_times, run_filetype)
        self._close_burst(burst_lines, burst_filetype)

    def _close_burst(self, lines: int, filetype: str) -> None:
        if lines:
            self.bursts[filetype].append(lines)

    def _close_run(self, key: str | None, times: Sequence[int], filetype: str) -> None:
        if key not in ("j", "k") or len(times) < RUN_MIN:
            return
        gaps = sorted(times[i + 1] - times[i] for i in range(len(times) - 1))
        self.runs.append((key, len(times), gaps[len(gaps) // 2], filetype))

    @property
    def total(self) -> int:
        return sum(self.keys.values())

    def rate(self, count: int) -> float:
        """Per 1000 keys, so windows of different length compare."""
        return 1000 * count / self.total if self.total else 0.0

    def count(self, forms: Sequence[str]) -> int:
        keys = sum(self.keys[form] for form in forms)
        cmds = sum(
            self.cmds[form.lstrip(":")] for form in forms if form.startswith(":")
        )
        return keys + cmds


def print_bursts(window: Window) -> None:
    """One journey per row: how far each uninterrupted scroll actually went."""
    if not window.bursts:
        return
    print(
        f"\nscroll bursts (vertical keys, one buffer, <={BURST_GAP_MS // 1000}s apart):"
    )
    header = f"  {'ft':<12} {'bursts':>6} {'lines':>7} {'med':>4} {'p90':>4} {'max':>5}"
    print(f"{header}  bursts over {LONG_BURST} lines")
    ranked = sorted(window.bursts.items(), key=lambda kv: -sum(kv[1]))[:6]
    for filetype, sizes in ranked:
        sizes = sorted(sizes)
        count, travelled = len(sizes), sum(sizes)
        median = sizes[count // 2]
        p90 = sizes[min(int(count * 0.9), count - 1)]
        long = [size for size in sizes if size > LONG_BURST]
        share = 100 * sum(long) / travelled
        print(
            f"  {filetype:<12} {count:>6} {travelled:>7} {median:>4} {p90:>4} "
            f"{sizes[-1]:>5}  {len(long)} carry {sum(long)} lines ({share:.0f}%)"
        )


def print_tree_vocabulary(window: Window) -> None:
    """Which of the tree's own movements are in the fingers, and which are not."""
    inside = window.keys_in_filetype.get("nerdtree")
    if not inside:
        return
    walked = inside["j"] + inside["k"]
    pressed = {key: inside[key] for key in TREE_KEYS if inside[key]}
    print(f"\nnerdtree ({sum(inside.values())} keys): j/k {walked}, o {inside['o']}")
    print(
        "  structural keys pressed:",
        ", ".join(f"{key} {count} ({TREE_KEYS[key]})" for key, count in pressed.items())
        or "none",
    )
    print(
        "  never pressed:",
        ", ".join(
            f"{key} ({desc})" for key, desc in TREE_KEYS.items() if key not in pressed
        )
        or "none",
    )


def print_window(window: Window) -> None:
    dates = sorted(window.dates)
    span = f"{dates[0]} .. {dates[-1]}" if dates else "(empty)"
    print(f"\n===== {window.label}: {span} =====")
    print(
        f"{len(dates)} days, {window.sessions} sessions, {window.total} keys, "
        f"{sum(window.cmds.values())} commands"
    )
    if not window.total:
        return

    print("\ntop keys:", window.keys.most_common(25))
    print("commands:", window.cmds.most_common(12))
    print("keys by filetype:", window.by_filetype.most_common(12))
    print("cwd:", window.cwds.most_common(6))

    print("\nwhere the keys go:")
    for name, members in MOTION_CLASSES.items():
        total = sum(window.keys[k] for k in members)
        detail = " ".join(f"{k}={window.keys[k]}" for k in members if window.keys[k])
        print(f"  {name:<9} {total:>5} {100 * total / window.total:>5.1f}%  {detail}")

    vertical = sum(window.keys[k] for k in MOTION_CLASSES["vertical"])
    print(f"\nvertical by filetype: {window.vertical_by_filetype.most_common(10)}")
    print_bursts(window)
    print_tree_vocabulary(window)
    in_runs = sum(r[1] for r in window.runs)
    print(f"runs of >={RUN_MIN}: {len(window.runs)}, keys spent in them: {in_runs}")
    if window.runs:
        longest = sorted(window.runs, key=lambda r: -r[1])[:8]
        print("longest (key, len, median gap ms, filetype):", longest)
        held = [r for r in window.runs if r[2] <= REPEAT_MS]
        held_keys = sum(r[1] for r in held)
        print(
            f"  {len(held)} of those ({held_keys} keys) at <={REPEAT_MS}ms "
            "median gap -- key-repeat, one press held"
        )
    vertical_share = 100 * vertical / window.total
    print(f"\nvertical movement is {vertical_share:.0f}% of every key pressed")

    # The filetypes that soak up the most vertical movement are where a better
    # motion would pay; the keys pressed inside them say which one is missing.
    for filetype, _ in window.vertical_by_filetype.most_common(4):
        inside = window.keys_in_filetype[filetype]
        print(
            f"  in {filetype} ({sum(inside.values())} keys): {inside.most_common(10)}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keylog", default=KEYLOG)
    parser.add_argument("--dojo", default=DOJO)
    parser.add_argument(
        "--since",
        help="First day of the current window. Defaults to the day after the "
        "previous review, read from review.json.",
    )
    parser.add_argument(
        "--today",
        default=datetime.date.today().isoformat(),
        help="YYYY-MM-DD, stamped into review.json as the review date",
    )
    parser.add_argument(
        "--review",
        nargs="?",
        const="",
        help="Write review.json (counts and window only, drills left empty)",
    )
    args = parser.parse_args()

    sessions = read_sessions(args.keylog)
    if not sessions:
        sys.exit(f"no keystroke log in {args.keylog}")
    dates = sorted({date for date, _ in sessions})
    review_path = args.review or f"{args.keylog}/review.json"

    since = args.since
    previous = None
    if os.path.exists(review_path):
        previous = json.load(open(review_path))
        if not since and previous.get("generated"):
            since = day_after(previous["generated"])
    since = since or dates[0]

    before = Window(
        sessions, dates[0], day_before(since), "before (up to the previous review)"
    )
    now = Window(sessions, since, dates[-1], "since the previous review")
    full = Window(sessions, dates[0], dates[-1], "full retained window")

    if previous:
        print(f"previous review: {previous.get('generated')}, drills:")
        for drill in previous.get("drills", []):
            print(f"  {drill.get('keys')}: {drill.get('note')}")

    print_window(before)
    print_window(now)
    print_window(full)

    print("\n===== DOJO ENTRIES =====")
    print(
        f"{'group':<10} {'keys':<16} {'before/1k':>10} {'now/1k':>8} "
        f"{'before':>7} {'now':>5}  desc"
    )
    counts: dict[str, int] = {}
    for group, written, desc, _added in dojo_entries(args.dojo):
        forms = keytrans_forms(written)
        was, is_now = before.count(forms), now.count(forms)
        if was + is_now:
            counts[written] = was + is_now
        rates = f"{before.rate(was):>10.2f} {now.rate(is_now):>8.2f}"
        print(f"{group:<10} {written:<16} {rates} {was:>7} {is_now:>5}  {desc[:50]}")

    if args.review is not None:
        out = {
            "generated": args.today,
            "window": {
                "from": dates[0],
                "to": dates[-1],
                "days": len(dates),
                "sessions": full.sessions,
                "keys": full.total,
            },
            "counts": counts,
            "drills": [],
        }
        with open(review_path, "w") as fd:
            json.dump(out, fd, indent=2, ensure_ascii=False)
            fd.write("\n")
        print(f"\nwrote {review_path} -- {len(counts)} counts, drills left empty")


main()
