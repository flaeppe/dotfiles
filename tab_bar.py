# Custom kitty tab-bar hook, loaded from ~/.config/kitty/tab_bar.py.
# Spells out the project each tab belongs to and what is running in it,
# independent of which pane is focused or what that pane's own title says.

_MAX_PROJECT_LEN = 12


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
    tab = data["tab"]
    # Both project and running process come from the tab's oldest window, so
    # the label does not change depending on which pane has focus -- an
    # overlay on top of a split included.
    project = _project(tab.active_oldest_wd)
    if not project:
        return ""
    label = project.lstrip(".")[:_MAX_PROJECT_LEN]
    if not label:
        return ""
    if tab.active_oldest_exe:
        label = f"{label} {tab.active_oldest_exe}"
    return label
