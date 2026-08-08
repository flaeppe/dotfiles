#!/usr/bin/env python3
"""Aggregate the nvim keystroke log into the numbers a periodic review reads.

Counting only. Every judgement call -- which habit is worth a drill, whether a
binding should be pruned -- belongs to the reviewer, not to this file.
"""

import argparse
import collections
import datetime
import glob
import json
import os
import pathlib
import re
import sys

KEYLOG = os.path.expanduser("~/.local/state/nvim/keylog")
# <repo>/.claude/skills/keystroke-review/report.py, so the dotfiles root is four
# levels up. Derived rather than hardcoded: the repo is not checked out at the
# same path on every machine.
DOJO = pathlib.Path(__file__).resolve().parents[3] / "nvim/lua/plugins/dojo.lua"

# `keytrans` spells control keys with an upper-case letter; the Dojo writes them
# the way vim documents them. Same key, two spellings, so one has to be folded.
LEADER = "<Space>"

# A run of one key at this median gap or below was the keyboard repeating, not a
# finger pressing. macOS repeats at ~84ms at the fastest setting.
REPEAT_MS = 120
RUN_MIN = 5

MOTION_CLASSES = {
    "vertical": ["j", "k", "<Down>", "<Up>", "<C-D>", "<C-U>", "<C-F>", "<C-B>", "G", "gg"],
    "search": ["/", "?", "n", "N", "*", "#"],
    "inline": ["f", "F", "t", "T", "0", "$", "^", "w", "b", "e", "W", "B", "%"],
    "targeted": ["<C-O>", "<C-I>", "gd", "grd", "grr", "<C-E>", "<C-P>"],
    "edit": ["o", "O", "i", "a", "c", "d", "x", "p", "u", "<C-R>"],
}


def shift_day(date, days):
    stamp = datetime.date.fromisoformat(date) + datetime.timedelta(days=days)
    return stamp.isoformat()


def day_after(date):
    return shift_day(date, 1)


def day_before(date):
    return shift_day(date, -1)


def dojo_entries(path):
    """[(group, keys, desc, added)] in the order the Dojo lists them."""
    src = open(path).read()
    table = src[src.index("local ENTRIES = {") : src.index("\n-- Written by")]
    pattern = (
        r'group\s*=\s*"([^"]+)"\s*,\s*keys\s*=\s*"([^"]+)"\s*,'
        r'\s*desc\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*added\s*=\s*"([^"]+)"'
    )
    return [m.groups() for m in re.finditer(pattern, table)]


def keytrans_forms(written):
    """A Dojo `keys` field -> the raw log spellings that count toward it.

    Two keys on one row ("¨f  åf") are one habit and count together.
    """
    forms = []
    for key in written.split():
        key = key.replace("<Leader>", LEADER)
        key = re.sub(r"<C-(\w)>", lambda m: "<C-%s>" % m.group(1).upper(), key)
        forms.append(key)
    return forms


def read_sessions(keylog):
    """[(date, [record, ...])] -- one entry per session file, chronological."""
    out = []
    for path in sorted(glob.glob(f"{keylog}/keys-*.jsonl")):
        date = re.search(r"keys-(\d{4}-\d{2}-\d{2})", path).group(1)
        records = []
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

    def __init__(self, sessions, lo, hi, label):
        self.label = label
        self.keys = collections.Counter()
        self.cmds = collections.Counter()
        self.by_filetype = collections.Counter()
        self.vertical_by_filetype = collections.Counter()
        self.keys_in_filetype = collections.defaultdict(collections.Counter)
        self.runs = []  # (key, length, median gap ms, filetype)
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

    def _scan(self, records, vertical):
        filetype, cwd = "", None
        run_key, run_times, run_filetype = None, [], ""
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
            if key == run_key:
                run_times.append(record["t"])
            else:
                self._close_run(run_key, run_times, run_filetype)
                run_key, run_times, run_filetype = key, [record["t"]], filetype
        self._close_run(run_key, run_times, run_filetype)

    def _close_run(self, key, times, filetype):
        if key not in ("j", "k") or len(times) < RUN_MIN:
            return
        gaps = sorted(times[i + 1] - times[i] for i in range(len(times) - 1))
        self.runs.append((key, len(times), gaps[len(gaps) // 2], filetype))

    @property
    def total(self):
        return sum(self.keys.values())

    def rate(self, count):
        """Per 1000 keys, so windows of different length compare."""
        return 1000 * count / self.total if self.total else 0.0

    def count(self, forms):
        keys = sum(self.keys[form] for form in forms)
        cmds = sum(self.cmds[form.lstrip(":")] for form in forms if form.startswith(":"))
        return keys + cmds


def print_window(window):
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
    print(f"runs of >={RUN_MIN}: {len(window.runs)}, keys spent in them: {sum(r[1] for r in window.runs)}")
    if window.runs:
        longest = sorted(window.runs, key=lambda r: -r[1])[:8]
        print("longest (key, len, median gap ms, filetype):", longest)
        held = [r for r in window.runs if r[2] <= REPEAT_MS]
        print(
            f"  {len(held)} of those ({sum(r[1] for r in held)} keys) at <={REPEAT_MS}ms "
            "median gap -- key-repeat, one press held"
        )
    print(f"\nvertical movement is {100 * vertical / window.total:.0f}% of every key pressed")

    # The filetypes that soak up the most vertical movement are where a better
    # motion would pay; the keys pressed inside them say which one is missing.
    for filetype, _ in window.vertical_by_filetype.most_common(4):
        inside = window.keys_in_filetype[filetype]
        print(f"  in {filetype} ({sum(inside.values())} keys): {inside.most_common(10)}")


def main():
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

    before = Window(sessions, dates[0], day_before(since), "before (up to the previous review)")
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
    print(f"{'group':<10} {'keys':<16} {'before/1k':>10} {'now/1k':>8} {'before':>7} {'now':>5}  desc")
    counts = {}
    for group, written, desc, added in dojo_entries(args.dojo):
        forms = keytrans_forms(written)
        was, is_now = before.count(forms), now.count(forms)
        if was + is_now:
            counts[written] = was + is_now
        print(
            f"{group:<10} {written:<16} {before.rate(was):>10.2f} {now.rate(is_now):>8.2f} "
            f"{was:>7} {is_now:>5}  {desc[:50]}"
        )

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
