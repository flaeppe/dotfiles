{ config, pkgs, ... }:

{
  home = {
    username = "ludo";
    homeDirectory = "/Users/ludo";
    language = {
      base = "en_US.UTF-8";
      collate = "C";
      ctype = "en_US.UTF-8";
      messages = "en_US.UTF-8";
      monetary = "sv_SE.UTF-8";
      time = "en_US.UTF-8";
    };
    packages = with pkgs; [
      coreutils
      croc
      curl
      fd
      htop
      git-crypt
      jq
      kubectl
      less
      ripgrep
      tree-sitter
      universal-ctags
    ];
    sessionVariables = {
      EDITOR = "nvim";
      # Set better color when printing folders
      LSCOLORS = "gxfxcxdxbxegedabagacad";
      CLICOLOR = 1;
      # Set date format language for ls
      LANG = "en_US.UTF-8";
      # Set SSL backend for curl
      PYCURL_SSL_LIBRARY = "openssl";
    };
    stateVersion = "23.11";
    # Setup default tags for universal-ctags
    file.".ctags.d/default.ctags".source = ./nvim/.ctags.d/default.ctags;
    # Add configuration for gpg-agent
    file.".gnupg/gpg-agent.conf".source = ./gnupg/gpg-agent.conf;
  };

  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        charset = "utf-8";
        end_of_line = "lf";
        indent_size = 2;
        trim_trailing_whitespace = true;
        insert_final_newline = true;
        indent_style = "space";
      };
      "Makefile" = {
        indent_style = "tab";
      };
      "*.py" = {
        indent_size = 4;
      };
    };
  };

  imports = [ ./git.nix ./fish/fish.nix ./nvim/nvim.nix ];

  programs = {
    home-manager.enable = true;

    bat = {
      enable = true;
      config = {
        theme = "OneHalfDark";
        map-syntax = [ ".ignore:.gitignore" ];
      };
      themes = {
        OneHalfDark = {
          src = pkgs.fetchFromGitHub {
            owner = "sonph";
            repo = "onehalf";
            rev = "75eb2e97acd74660779fed8380989ee7891eec56";
            sha256 = "F5gbDtGD2QBDGZOjr/OCJJlyQgxvQTsy8IoNNAjnDzQ=";
          };
          file = "sublimetext/OneHalfDark.tmTheme";
        };
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableFishIntegration = false;
      defaultCommand = "rg --files --hidden --glob '!.git/*'";
    };

    gh = {
      enable = true;
      settings = {
        aliases = { co = "pr checkout"; };
        git_protocol = "ssh";
      };
    };

    gpg = { enable = true; };

    tmux = {
      enable = true;
      # Set default shell for tmux
      shell = "${pkgs.fish}/bin/fish";
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
        ''
          bind s choose-tree -sZ -O name
        '' +
        # Turn on focus events to support (vim) autoread
        ''
          set-option -g focus-events on
        '' +
        # Set RGB capability (taken from healthcheck advice)
        ''
          set-option -sa terminal-overrides ',xterm-256color:RGB'
        '' +
        # Set scrollback buffer size
        ''
          set-option -g history-limit 50000
        ''
      );
    };
  };
}
