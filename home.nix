{ config, pkgs, ... }:

{
  home = {
    username = "ludo";
    homeDirectory = "/Users/ludo";
    packages = with pkgs; [
      jq
    ];
    sessionVariables = {
      EDITOR = "nvim";
    };
    stateVersion = "23.11";
  };

  programs = {
    home-manager.enable = true;

    bat = {
      enable = true;
      config = {
        theme = "OneHalfDark";
        map-syntax = [ ".ignore:.gitignore" ];
      };
      themes = {
        OneHalfDark = builtins.readFile (pkgs.fetchFromGitHub {
          owner = "sonph";
          repo = "onehalf";
          rev = "75eb2e97acd74660779fed8380989ee7891eec56";
          sha256 = "F5gbDtGD2QBDGZOjr/OCJJlyQgxvQTsy8IoNNAjnDzQ=";
        } + "/sublimetext/OneHalfDark.tmTheme");
      };
    };

    fzf = {
      enable = true;
      enableFishIntegration = false;
      defaultCommand = "rg --files --hidden --glob '!.git/*'";
    };

    gh = {
      enable = true;
      settings = {
        aliases = {
          co = "pr checkout";
        };
        git_protocol = "ssh";
      };
    };

    tmux = {
      enable = true;
      # Set default shell for tmux
      # TODO: shell = "{pkgs.fish}/bin/fish"; or something..
      shell = "/usr/local/bin/fish";
      # Make tmux able to show coloring (i.e. for fish)
      # MUST map with $TERM variable
      terminal = "screen-256color";
      # Set window indexing, starting from 1 instead of 0.
      # Helps with keybindings for quickswitch between windows.
      baseIndex = 1;
      # Set vim bindings
      keyMode = "vi";
      # Set escape time. (Taken from healthcheck advice)
      # See: https://github.com/neovim/neovim/wiki/FAQ#esc-in-tmux-or-gnu-screen-is-delayed
      escapeTime = 10;

      extraConfig = (
        # Order sessions by name
        "bind s choose-tree -sZ -O name\n" +
        # Turn on focus events to support (vim) autoread
        "set-option -g focus-events on\n" +
        # Set RGB capability (taken from healthcheck advice)
        "set-option -sa terminal-overrides ',xterm-256color:RGB'\n"
      );
    };

    git = {
      enable = true;
      userName = "Petter Friberg";
      userEmail = "petter_friberg@hotmail.com";

      signing = {
        key = "F188F74B056474E8";
        signByDefault = true;
      };

      diff-so-fancy = {
        enable = true;
      };

      extraConfig = {
        # Core
        init = {
          defaultBranch = "main";
        };
        pager = {
          show = "bat";
        };
        # Core -- UI
        color = {
          ui = "auto";
        };
        # Core commands -- status
        status = {
          showStash = true;
        };
        # Core commands -- network
        push = {
          default = "simple";
        };
        pull = {
          ff = "only";
        };
        # Core commands -- diff
        diff = {
          colorMoved = true;
          colorMovedWS = "allow-indentation-change";
        };
        # Core commands -- rebase
        rebase = {
          # Show stat output on rebase to show what changed
          stat = true;
          # Be more verbose than the default "ignore" about potentially
          # dropping data.
          missingCommitsCheck = "warn";
          # When using 'git rebase -i --exec "make test"' I want the
          # "make test" to run again on "git rebase --continue", the
          # default behaviour is to omit it.
          rescheduleFailedExec = true;
        };
        # Core commands -- [creating] objects
        commit = {
          verbose = true;
        };
        tag = {
          sort = "version:refname";
        };
      };

      ignores = [
        ".DS_STORE"
        ".venv"
        ".tags"
        ".nvimlog"
        "_private/"
      ];

      aliases = {
        up = "pull --rebase --autostash";
        slog = "log --pretty=oneline";
        local = "log origin..HEAD --pretty=oneline";
        lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        recentb = "!r() { refbranch=$1 count=$2; git for-each-ref --sort=-committerdate refs/heads --format='%(refname:short)|%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:blue)%(subject)|%(color:magenta)%(authorname)%(color:reset)' --color=always --count=\${count:-20} | while read line; do branch=$(echo \"$line\" | awk 'BEGIN { FS = \"|\" }; { print $1 }' | tr -d '*'); ahead=$(git rev-list --count \"\${refbranch:-origin/master}..\${branch}\"); behind=$(git rev-list --count \"\${branch}..\${refbranch:-origin/master}\"); colorline=$(echo \"$line\" | sed 's/^[^|]*|//'); echo \"$ahead|$behind|$colorline\" | awk -F'|' -v OFS='|' '{$5=substr($5,1,70)}1' ; done | ( echo \"ahead|behind||branch|lastcommit|message|author\\n\" && cat) | column -ts'|';}; r";
        oldestb = "for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(color:magenta)%(authorname)%(color:reset) (%(color:green)%(committerdate:relative)%(color:reset))'";
      };
    };
  };
}
