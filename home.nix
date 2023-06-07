{ config, pkgs, ... }:

{
  home = {
    username = "ludo";
    homeDirectory = "/Users/ludo";
    packages = with pkgs; [
      jq
    ];
    stateVersion = "23.11";
  };

  programs = {
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

    home-manager.enable = true;
  };
}
