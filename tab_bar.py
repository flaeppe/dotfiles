# Custom kitty tab-bar hook, loaded from ~/.config/kitty/tab_bar.py.
# Renders each tab's name (or, absent one, the checkout it sits in and what is
# running there) and, when marked, a state glyph -- independent of which pane
# is focused or what that pane's own title says. draw_tab tints each tab's
# background by repository, so the bar groups tabs at a glance without reading
# any of them -- this needs tab_bar_style set to "custom" (draw_title alone
# does not).

import os
import zlib
from typing import Any

from kitty.fast_data_types import Screen, get_boss
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabAccessor,
    TabBarData,
    as_rgb,
    draw_tab_with_fade,
)

_MAX_LABEL_LEN = 12

# The glyph a tab's name gets prefixed with when sam has marked it wanting
# attention (window user var claude_state, set by `sam session mark`). Same
# symbol kitty's own tab_activity_symbol used to draw, which is now disabled
# (tab_activity_symbol "" in darwin.nix) -- kitty's dot fires on any output
# in an unfocused tab and can't tell "grinding" from "wants you", so it
# competed with this one signal rather than adding a second. Revert that one
# config line to bring the generic dot back for non-Claude tabs.
_STATE_GLYPH = "● "
_STATE_VAR = "claude_state"

# Every tint is paired with the foreground kitty draws on it -- _GROUP with
# inactive_tab_foreground, _ACTIVE with active_tab_foreground (both in
# darwin.nix) -- and each pair is checked to at least 4.5:1, so no hue can
# make a label unreadable. Contrast comes from luminance, so hue and
# saturation are free: twelve hues at 27 degrees, high chroma, spanning
# 25-322 to stay clear of the red kitty's bell owns. Twelve rather than six
# because crc32 over ~68 repositories collides often enough at six that
# concurrently open tabs shared a tint.
_GROUP_PALETTE: tuple[int, ...] = (
    0x4D260A,
    0x373007,
    0x273607,
    0x133807,
    0x073812,
    0x073727,
    0x07363C,
    0x0C2F5E,
    0x15139B,
    0x420F7D,
    0x560B5C,
    0x5E0C3F,
)
_ACTIVE_PALETTE: tuple[int, ...] = (
    0x93450E,
    0x685C0A,
    0x47640A,
    0x21690A,
    0x0B6A1F,
    0x0A6849,
    0x0B6470,
    0x1259B5,
    0x403EEC,
    0x7917E8,
    0x9D11AA,
    0xAC1174,
)

# A tab in no checkout at all is not a repository that happens to hash to
# index 0, so it gets its own neutral pair rather than borrowing one.
_NO_CHECKOUT = 0x2A2A37
_NO_CHECKOUT_ACTIVE = 0x4A4A60


# One entry per distinct working directory this kitty process has drawn a tab
# for, which is a handful. Keyed on the directory because resolving one walks
# the filesystem, and the tab bar redraws far more often than a tab moves.
# Ceiling: a directory that becomes a checkout after being cached as "not one"
# keeps the old answer for the life of the process; clear this dict if that
# ever matters.
_CHECKOUT_CACHE: dict[str, tuple[str, str]] = {}

# What a linked worktree's `.git` file points at. The segment before it names
# the repository, wherever the worktree itself happens to sit.
_WORKTREE_MARKER = "/.git/worktrees/"


def _read_repository(git_file: str) -> str:
    """The repository a linked worktree's `.git` file belongs to, or ""."""
    try:
        with open(git_file) as handle:
            gitdir = handle.read(4096)
    except OSError:
        return ""
    gitdir = gitdir.partition("gitdir:")[2].strip()
    repository, marker, _ = gitdir.partition(_WORKTREE_MARKER)
    return os.path.basename(repository) if marker else ""


def _checkout(cwd: str) -> tuple[str, str]:
    """The repository name and worktree name of the checkout holding `cwd`.

    The worktree name is "" for a repository's own checkout, and both are ""
    when `cwd` sits in no checkout at all.
    """
    if not cwd:
        return "", ""
    cached = _CHECKOUT_CACHE.get(cwd)
    if cached is not None:
        return cached

    resolved = "", ""
    directory = os.path.abspath(cwd)
    while True:
        git = os.path.join(directory, ".git")
        # A repository's own checkout carries a directory; every linked
        # worktree carries a file naming where its real one lives.
        if os.path.isdir(git):
            resolved = os.path.basename(directory), ""
            break
        if os.path.isfile(git):
            repository = _read_repository(git)
            name = os.path.basename(directory)
            resolved = (repository or name), ("" if repository == name else name)
            break
        parent = os.path.dirname(directory)
        if parent == directory:
            break
        directory = parent

    _CHECKOUT_CACHE[cwd] = resolved
    return resolved


def _group_color(repository: str, is_active: bool) -> int:
    if not repository:
        return _NO_CHECKOUT_ACTIVE if is_active else _NO_CHECKOUT
    palette = _ACTIVE_PALETTE if is_active else _GROUP_PALETTE
    return palette[zlib.crc32(repository.encode()) % len(palette)]


# _tab_name and _tab_state both reach past TabBarData/TabAccessor into
# kitty's own Tab object -- get_boss().tab_for_id is private API with no
# stability guarantee (verified against kitty 0.48.0's tab_bar.py source;
# check it still exists on any kitty upgrade). An exception here would
# otherwise take down the whole tab bar, not just this one tab, so every
# call is wrapped and falls back to what the tab would have rendered anyway.


def _tab_name(tab_id: int) -> str:
    """The tab's own explicit name (kitten @ set-tab-title), or "" if none
    was ever set. Empty, not kitty's window-title fallback -- callers need
    to tell "sam named this" apart from "showing some window's own title"."""
    try:
        kitty_tab = get_boss().tab_for_id(tab_id)
        return kitty_tab.name if kitty_tab else ""
    except Exception:
        return ""


def _tab_state(tab_id: int) -> str:
    """claude_state from whichever window in the tab carries it, or "" if
    none do. Checked across every window, not just the active pane, so the
    glyph survives an overlay or a split sam did not target directly."""
    try:
        kitty_tab = get_boss().tab_for_id(tab_id)
        if kitty_tab is None:
            return ""
        for window in kitty_tab:
            state = window.user_vars.get(_STATE_VAR, "")
            if state:
                return state
        return ""
    except Exception:
        return ""


def draw_title(data: dict[str, Any]) -> str:
    tab = data["tab"]
    prefix = _STATE_GLYPH if _tab_state(tab.tab_id) else ""

    name = _tab_name(tab.tab_id)
    if name:
        return prefix + name[:_MAX_LABEL_LEN]

    # Both checkout and running process come from the tab's oldest window, so
    # the label does not change depending on which pane has focus -- an
    # overlay on top of a split included.
    repository, worktree = _checkout(tab.active_oldest_wd)
    label = repository.lstrip(".")[:_MAX_LABEL_LEN]
    if not label:
        return prefix
    if worktree:
        # The worktree is what distinguishes this tab from the repository's
        # other checkouts, so it keeps its own budget rather than sharing the
        # repository's and being truncated away.
        label = f"{label}/{worktree[:_MAX_LABEL_LEN]}"
    if tab.active_oldest_exe:
        label = f"{label} {tab.active_oldest_exe}"
    return prefix + label


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    # `tab` here is a TabBarData, which carries no working directory at all --
    # only the title template is handed a TabAccessor. Building one from the
    # tab id is what gives this function the same view the label has; reading
    # the field off `tab` raises, and kitty answers that by silently drawing
    # the tab uncoloured.
    repository, _ = _checkout(TabAccessor(tab.tab_id).active_oldest_wd)
    screen.cursor.bg = as_rgb(_group_color(repository, tab.is_active))
    return draw_tab_with_fade(
        draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data
    )
