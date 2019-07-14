#!/usr/bin/env fish

switch (uname)
    case Darwin
            brew install bat
    case Linux
            sudo pacman -S --noconfirm --needed bat
    case '*'
            printf 'ERROR: No installation matching on %s\n' (uname)
            exit 1
end
