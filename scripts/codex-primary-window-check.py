#!/usr/bin/env python3
"""Exit 0 iff `sam usage codex --json` (on stdin) shows the primary window
resetting roughly 5h from now; exit 1 otherwise. Used by
codex-daily-poke.sh to confirm a poke actually activated the window rather
than trusting `codex exec`'s own exit code alone.
"""

import datetime
import json
import sys


def main() -> int:
    windows = json.load(sys.stdin)
    primary = next(w for w in windows if w["stack"] == "codex" and "h" in w["label"])
    # sam renders "resets" in this machines own local zone (time.Local on
    # its side) -- drop the trailing tz abbreviation and attach the current
    # local zone rather than parsing it. Known ceiling: wrong within a few
    # minutes of a year boundary, irrelevant for a same-day 5h window.
    text = " ".join(primary["resets"].split(" ")[:-1])
    year = datetime.datetime.now().year
    naive = datetime.datetime.strptime(f"{year} {text}", "%Y %b %d %H:%M")
    local_tz = datetime.datetime.now().astimezone().tzinfo
    reset_at = naive.replace(tzinfo=local_tz)
    now = datetime.datetime.now().astimezone()
    delta_hours = (reset_at - now).total_seconds() / 3600
    return 0 if 0 < delta_hours <= 5.5 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(1)
