{
  description = "Dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nix utils for Mac App launchers. Helps launching .app programs from Spotlight
    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = { nixpkgs, home-manager, flake-utils, mac-app-util, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kanagawaRepo = pkgs.fetchFromGitHub {
          owner = "rebelot";
          repo = "kanagawa.nvim";
          rev = "cc3b68b08e6a0cb6e6bf9944932940091e49bb83";
          sha256 = "0mi15a4cxbrqzwb9xl47scar8ald5xm108r35jxcdrmahinw62rz";
        };
        username = "petter.friberg";
      in {
        packages.homeConfigurations = {
          ${username} = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              mac-app-util.homeManagerModules.default
              ({ pkgs, ... }: {
                home = {
                  inherit username;
                  homeDirectory = "/Users/${username}";
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
                    "Makefile" = {
                      indent_style = "tab";
                      indent_size = "unset";
                    };
                    "*.py" = { indent_size = 4; };
                    "*.lua" = { indent_size = 4; };
                    "*.fish" = { indent_size = 4; };
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
                    fileWidgetOptions = [
                      "--walker-skip .git,node_modules,.direnv,.venv,venv,.pytest_cache,.ruff_cache,__pycache__"
                      "--preview 'bat -n --color=always {}'"
                    ];
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
                      shell_integration = "enabled";
                      # kitty-scrollback.nvim Kitten alias
                      action_alias =
                        "kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
                      font_size = "8.0";
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
                      # Browse scrollback buffer in nvim
                      "ctrl+f" = "kitty_scrollback_nvim --nvim-args -n";
                      # Browse output of the last shell command in nvim
                      "kitty_mod+g" =
                        "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
                    };
                    themeFile = "kanagawa";
                  };
                };
              })
            ];
          };
        };
      });
}
