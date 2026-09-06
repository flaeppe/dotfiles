#!/usr/bin/env python3
# kitty geninclude script for the cmd+s project jump table (see darwin.nix).
# Emits one `map cmd+s>{letter} goto_session {path}` line per session file
# under ~/anyfin/*/_private/*.kitty-session, plus dotfiles and .me below,
# letters assigned by sorted name.

import glob
import os
import string

STATIC = {
    "dotfiles": "~/.dotfiles/dotfiles.kitty-session",
    "me": "~/anyfin/.me/sam.kitty-session",
}


def discovered():
    pattern = os.path.expanduser("~/anyfin/*/_private/*.kitty-session")
    for path in glob.glob(pattern):
        repo = os.path.basename(os.path.dirname(os.path.dirname(path)))
        filename = os.path.basename(path)
        yield repo, f"~/anyfin/{repo}/_private/{filename}"


sessions = dict(discovered())
sessions.update(STATIC)

for letter, name in zip(string.ascii_lowercase, sorted(sessions)):
    print(f"map cmd+s>{letter} goto_session {sessions[name]}")
