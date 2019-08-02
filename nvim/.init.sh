#!/usr/bin/env fish

switch (uname)
    case Darwin
            brew install neovim
            brew tap universal-ctags/universal-ctags
            brew install --HEAD universal-ctags
    case Linux
            sudo pacman -S neovim
    case '*'
            printf 'ERROR: No installation matching on %s\n' (uname)
            exit 1
end
