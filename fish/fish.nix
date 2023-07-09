{ config, pkgs, ... }:
{
  # Fish completions, as there's no available config we do this manually
  xdg.configFile."fish/completions/workon.fish".source = ./completions/workon.fish;

  programs = {
    fish = {
      enable = true;
      plugins = [
        # Needed when having fish as default macOS shell, so that `~/.nix-profile/bin`
        # is picked up properly
        {
          name = "nix-env";
          src = pkgs.fetchFromGitHub {
            owner = "lilyball";
            repo = "nix-env.fish";
            rev = "7b65bd228429e852c8fdfa07601159130a818cfa";
            sha256 = "RG/0rfhgq6aEKNZ0XwIqOaZ6K5S4+/Y5EEMnIdtfPhk=";
          };
        }
      ];
      shellAliases = {
        ls = "ls -h --color=auto";
      };
      shellInit = ''
        # Disable fish greeting
        set fish_greeting
        # Disable 'activate.fish' auto setting and displaying fish status
        set -x VIRTUAL_ENV_DISABLE_PROMPT 1
      '';
      interactiveShellInit = ''
        # Starting TMUX on startup, if tmux exists
        # If existing session exists -> attach. Otherwise new tmux session
        if begin; type -q tmux; and test -z (echo $TMUX); end
          tmux attach
          if test $status -gt 0
            tmux new-session
          end
        end

        # Init pyenv
        if begin; type -q pyenv; end
          source (pyenv init -|psub)
        end
      '';
      functions = {
        fish_prompt = {
          description = "Write out the prompt";
          body = ''
            ${builtins.readFile ./functions/fish_prompt.fish}
          '';
        };
        fish_user_key_bindings = {
          description = "Set custom key bindings";
          body = ''
            bind \cc 'commandline ""'  # Control-c will reset the line
          '';
        };
        flog = {
          description = "Fuzzy git log search that outputs the selected hash";
          body = ''
            git log --color=always --decorate --oneline | fzf --ansi --reverse | awk '{ print $1 }'
          '';
        };
        man = {
          description = "Colorised man pages with a wrapper";
          body = ''
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
          '';
        };
        workon = {
          description = "Moves you to the project directory and activates the associated virtualenv, if any found";
          body = ''
            ${builtins.readFile ./functions/workon.fish}
          '';
        };
      };
    };
  };
}
