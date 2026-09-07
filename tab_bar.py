# Custom kitty tab-bar hook, loaded from ~/.config/kitty/tab_bar.py.
# Renders each tab's name (or, absent one, the project it belongs to and
# what is running in it) and, when marked, a state glyph -- independent of
# which pane is focused or what that pane's own title says. draw_tab tints
# each tab's background by project, so the bar groups tabs at a glance
# without reading any of them -- this needs tab_bar_style set to "custom"
# (draw_title alone does not).

import zlib
from typing import Any

from kitty.fast_data_types import Screen, get_boss
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_tab_with_fade

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

# Dark tints only: the bar's one text colour (#dcd7ba) has to read on every
# entry, so nothing here gets close to it in brightness. No red -- kitty's
# own bell/activity indicator owns that. Index 0 is the pre-010 default
# background, kept so an unrecognised (empty-project) tab looks unchanged.
# _ACTIVE holds the same hues, one step brighter, so the focused tab still
# reads as focused once colour stops being state's channel.
_GROUP_PALETTE: tuple[int, ...] = (
    0x2A2A37,  # slate
    0x223249,  # blue
    0x26332B,  # green
    0x332A3D,  # purple
    0x3A2E28,  # brown
    0x22333A,  # teal
)
_ACTIVE_PALETTE: tuple[int, ...] = (
    0x3A3A4A,
    0x2F4666,
    0x35473A,
    0x453A52,
    0x4D3F36,
    0x2F4750,
)


def _project(cwd: str) -> str:
    if not cwd:
        return ""
    parts = cwd.rstrip("/").split("/")
    if "anyfin" in parts:
        i = parts.index("anyfin")
        if i + 1 < len(parts):
            return parts[i + 1]
    if ".dotfiles" in parts:
        return ".dotfiles"
    return parts[-1] if parts else ""


def _group_color(project: str, is_active: bool) -> int:
    palette = _ACTIVE_PALETTE if is_active else _GROUP_PALETTE
    if not project:
        return palette[0]
    return palette[zlib.crc32(project.encode()) % len(palette)]


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

    # Both project and running process come from the tab's oldest window, so
    # the label does not change depending on which pane has focus -- an
    # overlay on top of a split included.
    project = _project(tab.active_oldest_wd)
    if not project:
        return prefix
    label = project.lstrip(".")[:_MAX_LABEL_LEN]
    if not label:
        return prefix
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
    project = _project(tab.active_oldest_wd)
    screen.cursor.bg = as_rgb(_group_color(project, tab.is_active))
    return draw_tab_with_fade(
        draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data
    )
