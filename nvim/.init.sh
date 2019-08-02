#!/usr/bin/env fish

switch (uname)
    case Darwin
            brew install neovim
    case Linux
            sudo pacman -S neovim
    case '*'
            printf 'ERROR: No installation matching on %s\n' (uname)
            exit 1
end
