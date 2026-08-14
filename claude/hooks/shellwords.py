"""Reading a shell command line closely enough to tell an invocation from text.

A tool name means a command is being run only where a command starts. Inside a
quoted string, a heredoc body or an argument it is text someone wrote -- a commit
message, a grep pattern -- and a hook that cannot tell the two apart fires on
prose. Every consumer here needs that distinction, and needs it to survive input
a shell lexer rejects.
"""

from __future__ import annotations

import re
import shlex
from typing import Final

# Shell punctuation, which the lexer reports as its own word only where the shell
# would act on it. Quoted punctuation stays inside the word it belongs to.
OPERATORS: Final = frozenset("|&;<>()")

# A leading `VAR=value` does not consume the command position.
ASSIGNMENT: Final = re.compile(r"^[A-Za-z_]\w*=")

# Wrappers that stand in front of the real command, together with their own flags
# and numeric arguments -- `timeout 5 git push` runs git, not 5. Ceiling: a
# wrapper absent from this list reads as the command itself, so whatever it runs
# goes unseen; add names as they show up.
WRAPPERS: Final = frozenset(
    ("sudo", "command", "env", "time", "timeout", "nice", "xargs")
)


def _lex(command: str, quotes: str, escape: str) -> list[str] | None:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.quotes = quotes
    lexer.escape = escape
    try:
        return list(lexer)
    except ValueError:
        return None


def strict_words_of(command: str) -> list[str] | None:
    """Shell words with quoting resolved, or None if the quoting will not parse.

    For reading a value out of a command line, where a half-parsed word is worse
    than no answer.
    """
    return _lex(command, quotes="'\"", escape="\\")


def words_of(command: str) -> list[str]:
    """Shell words, read again with quoting off for text a lexer rejects.

    The second pass cannot fail and only ever splits into more words, so a
    command position stays a command position: an unbalanced apostrophe in a
    heredoc body costs no verdict.
    """
    parsed = strict_words_of(command)
    if parsed is not None:
        return parsed
    return _lex(command, quotes="", escape="") or []


def is_operator(word: str) -> bool:
    return bool(word) and set(word) <= OPERATORS


def sub_commands(words: list[str]) -> list[list[str]]:
    """Each shell sub-command as its own word list."""
    segments: list[list[str]] = []
    current: list[str] = []
    for word in words:
        if is_operator(word):
            if current:
                segments.append(current)
            current = []
            continue
        current.append(word)
    if current:
        segments.append(current)
    return segments


def leading_command(words: list[str]) -> tuple[str | None, int]:
    """(the word a sub-command runs, its index), skipping what stands in front.

    An assignment, a wrapper, and that wrapper's own flags and numeric arguments
    all precede the real command rather than being it.
    """
    after_wrapper = False
    for index, word in enumerate(words):
        if ASSIGNMENT.match(word):
            continue
        if word in WRAPPERS:
            after_wrapper = True
            continue
        if after_wrapper and (word.startswith("-") or word.isdigit()):
            continue
        return word, index
    return None, 0
