#!/usr/bin/env fish

switch (uname)
    case Darwin
            brew install fish fzf ripgrep
    case Linux
            sudo pacman -S --noconfirm --needed fish fzf ripgrep
    case '*'
            printf 'ERROR: No installation matching on %s\n' (uname)
            exit 1
end
