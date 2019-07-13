function man --description "Colorised man pages with a wrapper"
    set -x LESS_TERMCAP_mb (set_color green)  # Begin blinking 
    set -x LESS_TERMCAP_md (set_color --bold green)  # Start of bold
    set -x LESS_TERMCAP_me (set_color normal)  # End of all formatting
    set -x LESS_TERMCAP_se (set_color normal)  # End standout-mode 
    set -x LESS_TERMCAP_so (set_color yellow)  # Begin standout-mode - info box 
    set -x LESS_TERMCAP_ue (set_color normal)  # End underline 
    set -x LESS_TERMCAP_us (set_color --underline red)  # Begin underline

    # ANSI "color" escape sequences are output in "raw" form
    set -x LESS "-R"

    command man $argv
end
