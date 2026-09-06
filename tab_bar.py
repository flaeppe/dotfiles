# Custom kitty tab-bar hook, loaded from ~/.config/kitty/tab_bar.py.
# Colours each tab by the project it belongs to, independent of which pane is
# focused or what that pane's own title says.

import zlib

from kitty.tab_bar import Formatter

# Kanagawa accents (see kitty/kanagawa.conf), skipping red -- kitty prepends
# the bell/activity indicator in fmt.fg.red, and a project sharing that hue
# would blend into it -- and skipping the greys, which don't read as colour
# against the theme's own grey inactive-tab text.
_PALETTE = ("76946a", "c0a36e", "7e9cd8", "957fb8", "6a9589")


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


def draw_title(data: dict) -> str:
    # active_oldest_wd: the cwd of the tab's oldest window, so a tab's colour
    # doesn't change depending on which split pane last had focus.
    project = _project(data["tab"].active_oldest_wd)
    if not project:
        return ""
    tag = project.lstrip(".")[:4]
    if not tag:
        return ""
    color = _PALETTE[zlib.crc32(project.encode()) % len(_PALETTE)]
    return f"{getattr(Formatter.fg, '_' + color)}{tag}"
