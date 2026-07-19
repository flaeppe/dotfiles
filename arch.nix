{ pkgs, unstable, ... }:

{
  home = {
    username = "ludo";
    homeDirectory = "/home/ludo";
    stateVersion = "25.11";

    packages = with pkgs; [
      coreutils
      curl
      fd
      fzf
      gnumake
      jq
      less
      nodejs
      pkg-config
      python3
      ripgrep
      tmux
      tree
      unzip
      uv
      wget
      xclip
      zip
      zoxide
    ];

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
    # Home Manager's Neovim wrapper carries the declared plugin runtime.
    # It must win over Arch's /usr/bin/nvim in shells and desktop sessions.
    sessionPath = [ "$HOME/.nix-profile/bin" "$HOME/.local/bin" ];
  };

  # Nix reads this user configuration after the first switch.  The system
  # daemon remains owned by Arch; this only enables the modern CLI and flakes.
  xdg.configFile."nix/nix.conf".text = ''
    experimental-features = nix-command flakes
  '';

  # A systemd --user ssh-agent.service (pre-existing, hand-installed circa
  # 2019, WantedBy=default.target) already runs for the whole boot and
  # survives i3 restarts -- it just isn't exported into the session. Point
  # SSH_AUTH_SOCK at its fixed socket so kitty/git see the running agent.
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";

  # Same long cache-ttl as the macOS/work config -- no arch-specific reason
  # to prompt more often on a personal box.
  home.file.".gnupg/gpg-agent.conf".source = ./gnupg/gpg-agent.conf;

  programs = {
    home-manager.enable = true;

    bat = {
      enable = true;
      config = { map-syntax = [ ".ignore:.gitignore" ]; };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
      defaultCommand = "rg --files --hidden --glob '!.git/*'";
      fileWidgetOptions = [
        "--walker-skip .git,node_modules,.direnv,.venv,venv,.pytest_cache,.ruff_cache,__pycache__"
        "--preview 'bat -n --color=always {}'"
      ];
    };

    # X11 has no OS-level pasteboard daemon like macOS -- xclip talks to the
    # X selection directly. Arch-only: macOS already has real pbcopy/pbpaste.
    fish.shellAliases = {
      pbcopy = "xclip -selection clipboard";
      pbpaste = "xclip -selection clipboard -o";
    };

    kitty = {
      enable = true;
      # The stable nixpkgs pin here ships kitty 0.44.0, whose GLX context
      # creation fails against this host's current NVIDIA driver
      # ("GLX: No GLXFBConfigs returned"). Track unstable, same as the
      # Darwin Kitty setup, to stay ahead of that.
      #
      # Separately: nix's own dynamic linker never falls back to system
      # library directories, so kitty's own process can't find the
      # proprietary NVIDIA driver files under /usr/lib on this non-NixOS
      # host without LD_LIBRARY_PATH pointing there. That var must NOT leak
      # session-wide (it segfaults unrelated nix-built binaries, e.g. Go
      # programs' pthread_create, by shadowing their own glibc with Arch's),
      # so it's wrapped onto just the kitty/kitten binaries here, and
      # `env LD_LIBRARY_PATH` below strips it again before it spawns the
      # actual shell, keeping it out of every program run inside kitty too.
      package = pkgs.symlinkJoin {
        name = "kitty-nvidia-wrapped";
        paths = [ unstable.kitty ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/kitty --set LD_LIBRARY_PATH /usr/lib
          wrapProgram $out/bin/kitten --set LD_LIBRARY_PATH /usr/lib
        '';
      };
      # Shared visual baseline with the Darwin Kitty setup. The surrounding
      # bindings and integration remain platform-specific.
      themeFile = "kanagawa";
      settings = {
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/mykitty";
        font_family = "Iosevka";
        font_size = "11.0";
        shell = "${pkgs.fish}/bin/fish";
        shell_integration = "enabled";
        env = "LD_LIBRARY_PATH";
        # kitty-scrollback.nvim Kitten alias (nvim side already set up in
        # nvim.nix, shared with the macOS config)
        action_alias =
          "kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
      };
      keybindings = {
        # Browse scrollback buffer in nvim
        "ctrl+f" = "kitty_scrollback_nvim --nvim-args -n";
        # Browse output of the last shell command in nvim
        "kitty_mod+g" =
          "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
      };
    };

    neovim = {
      enable = true;
      defaultEditor = true;
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

}
