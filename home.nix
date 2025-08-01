{ pkgs, ... }:
let
  kanagawaRepo = pkgs.fetchFromGitHub {
    owner = "rebelot";
    repo = "kanagawa.nvim";
    rev = "cc3b68b08e6a0cb6e6bf9944932940091e49bb83";
    sha256 = "0mi15a4cxbrqzwb9xl47scar8ald5xm108r35jxcdrmahinw62rz";
  };
in {
  home = {
    username = "petter.friberg";
    homeDirectory = "/Users/petter.friberg";
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
      curl
      fd
      htop
      git-crypt
      jq
      kubectl
      less
      ripgrep
      (google-cloud-sdk.withExtraComponents
        [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    ];
    # This doesn't work though hm-session-vars.fish is updated..
    sessionPath = [ "$HOME/.local/bin" ];
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
    stateVersion = "24.11";
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
      "Makefile" = { indent_style = "tab"; };
      "*.py" = { indent_size = 4; };
    };
  };

  imports = [ ./git/git.nix ./fish/fish.nix ./nvim/nvim.nix ];

  programs = {
    home-manager.enable = true;

    bat = {
      enable = true;
      config = {
        theme = "Kanagawa";
        map-syntax = [ ".ignore:.gitignore" ];
      };
      themes = {
        Kanagawa = {
          src = kanagawaRepo;
          file = "extras/tmTheme/kanagawa.tmTheme";
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

    kitty = {
      enable = true;
      settings = {
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/mykitty";
        kitty_mod = "ctrl+shift";
      };
      keybindings = {
        "cmd+shift+l" = "next_tab";
        "cmd+shift+h" = "previous_tab";
        "ctrl+j" = "kitten vim_nav.py bottom ctrl+j";
        "ctrl+k" = "kitten vim_nav.py top ctrl+k";
        "ctrl+h" = "kitten vim_nav.py left ctrl+h";
        "ctrl+l" = "kitten vim_nav.py right ctrl+l";
        "kitty_mod+1" = "goto_tab 1";
        "kitty_mod+2" = "goto_tab 2";
        "kitty_mod+3" = "goto_tab 3";
        "kitty_mod+4" = "goto_tab 4";
        "kitty_mod+5" = "goto_tab 5";
        "kitty_mod+6" = "goto_tab 6";
        "kitty_mod+7" = "goto_tab 7";
        "kitty_mod+8" = "goto_tab 8";
        "kitty_mod+9" = "goto_tab 9";
        "kitty_mod+0" = "goto_tab 10";
      };
      themeFile = "kanagawa";
    };
  };
}
