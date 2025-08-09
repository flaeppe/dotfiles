from kitty.boss import Boss
from kittens.tui.handler import result_handler


def main():
    pass


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Boss):
    """
    Moves to a neighboring window if one exists, otherwise a neigboring tab if one
    exists and navigation direction is left or right.
    """
    direction = args[1]
    neighbor = boss.active_tab.neighboring_group_id(direction)
    if neighbor is not None:
        boss.active_tab.neighboring_window(direction)
    # No neighboring window, move tab on left(<--) and right(-->)
    elif direction == "left":
        boss.previous_tab()
        # TODO: Focus rightmost window
    elif direction == "right":
        # Move to next tab
        boss.next_tab()
        # Focus the first window (windows are counted clockwise in every layout)
        boss.active_tab.first_window()
