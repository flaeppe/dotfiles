{ pkgs, lib, unstable, ... }:

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
    packages = (with pkgs; [
      coreutils
      curl
      dive
      fd
      git-crypt
      glow
      (google-cloud-sdk.withExtraComponents
        [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
      htop
      jq
      k9s
      kubectl
      less
      openssl
      ripgrep
      terminal-notifier
      uv
      yq-go
    ]) ++ [
      (pkgs.writeShellScriptBin "claude" ''
        set -euo pipefail
        _pass() { ${pkgs.pass}/bin/pass show "$1" 2>/dev/null; }
        _v="$(_pass dev/context7-api-key)";    [[ -n "$_v" ]] && export CONTEXT7_API_KEY="$_v"
        exec "$HOME/.local/bin/claude" "$@"
      '')
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
    stateVersion = "25.11";
    # Add configuration for gpg-agent
    file.".gnupg/gpg-agent.conf".source = ./gnupg/gpg-agent.conf;
    # Spells out each tab's project and what's running in it, from its oldest
    # window's cwd. Kept out of tab_title_template itself: that template
    # evaluates in a sandboxed eval() against a fixed set of builtins (see
    # safe_builtins in kitty's tab_bar.py), so turning an arbitrary cwd into a
    # project name needs real Python string handling, not an f-string.
    file.".config/kitty/tab_bar.py".source = ./tab_bar.py;
    # What clicking a path does: a source file opens in nvim, a .log tails
    # live, rather than falling through to the system opener.
    file.".config/kitty/open-actions.conf".source = ./open-actions.conf;

    activation = let
      ptf = "${pkgs.bash}/bin/bash ${./scripts/pass-to-file.sh}";
      passPath = "${pkgs.pass}/bin:${pkgs.coreutils}/bin";
    in {
      writeSshKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        PATH="${passPath}:$PATH"; export PATH
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        ${ptf} ssh/id-ed25519              "$HOME/.ssh/id_ed25519"              600
        ${ptf} ssh/id-ed25519.pub          "$HOME/.ssh/id_ed25519.pub"          644
        ${ptf} ssh/id-rsa                  "$HOME/.ssh/id_rsa"                  600
        ${ptf} ssh/id-rsa.pub              "$HOME/.ssh/id_rsa.pub"              644
        ${ptf} ssh/google-compute-engine     "$HOME/.ssh/google_compute_engine"     600
        ${ptf} ssh/google-compute-engine.pub "$HOME/.ssh/google_compute_engine.pub" 644
      '';

      writeNpmrc = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        PATH="${passPath}:$PATH"; export PATH
        ${ptf} dev/npm-token "$HOME/.npmrc" 600
      '';
    };
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
      # The fzf-fish plugin owns the interactive key bindings. fzf's own shell
      # integration binds ctrl-t/ctrl-r/alt-c on top of the plugin's, so the two
      # must not both be active. Widget options (FZF_CTRL_T_OPTS and friends)
      # belong to that disabled integration and are configured on the plugin
      # instead; defaultCommand still applies to bare `fzf` invocations.
      enableFishIntegration = false;
      defaultCommand = "rg --files --hidden --glob '!.git/*'";
    };

    gh = {
      package = unstable.gh;
      enable = true;
      settings = {
        aliases = { co = "pr checkout"; };
        git_protocol = "ssh";
      };
    };

    gpg = { enable = true; };

    password-store = {
      enable = true;
      settings = { PASSWORD_STORE_CLIP_TIME = "45"; };
    };

    kitty = {
      package = unstable.kitty;
      enable = true;
      settings = {
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/mykitty";
        kitty_mod = "ctrl+shift";
        shell = "${pkgs.fish}/bin/fish";
        shell_integration = "enabled";
        # kitty-scrollback.nvim Kitten alias
        action_alias =
          "kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
        font_size = "8.0";
        # {custom} calls tab_bar.py's draw_title to render the tab label; it is
        # the template's only field so no window's title, overlay included,
        # can replace it.
        tab_title_template = "{custom}";
        # draw_tab also lives in tab_bar.py, tinting each tab's background by
        # project -- only reachable when the style is "custom".
        tab_bar_style = "custom";
        # tab_bar.py's own state glyph is the only "wants attention" signal
        # now -- kitty's generic dot fired on any output in an unfocused tab
        # and couldn't tell "grinding" from "wants you", so it only
        # duplicated that signal. Revert to "●" to bring it back.
        tab_activity_symbol = "";
        # An ordinary shell command (build, test run) finishing unfocused, past
        # 10s. Fires on OSC 133 shell completion, so it never sees a Claude
        # session -- that is one continuous foreground process with no such
        # signal.
        notify_on_cmd_finish = "invisible 10.0";
        # Focus is signalled twice, because one channel alone is faint at a
        # glance: the background steps up a palette entry (tab_bar.py) and
        # the text steps up with it. Each foreground is contrast-checked
        # against the palette it is drawn on -- inactive on _GROUP_PALETTE,
        # active on _ACTIVE_PALETTE -- so changing one means rechecking both.
        active_tab_foreground = "#f2efe4";
        inactive_tab_foreground = "#9c978a";
        # Only reached if tab_bar.py's draw_tab raises, when kitty falls back
        # to its own renderer; both are set so that path stays legible and
        # keeps focus the brighter of the two.
        active_tab_background = "#4a4a60";
        inactive_tab_background = "#2a2a37";
        mark1_foreground = "black";
        mark1_background = "red";
        mark2_foreground = "black";
        mark2_background = "yellow";
        mark3_foreground = "white";
        mark3_background = "magenta";
      };
      keybindings = {
        "cmd+shift+l" = "next_tab";
        "cmd+shift+h" = "previous_tab";
        "cmd+p" = "launch --type=overlay fish -i -c tab-picker";
        "kitty_mod+m" = ''toggle_marker iregex 1 \bERROR\b|\bFATAL\b 2 \bFAIL\b 3 \bpanic\b'';
        "kitty_mod+j" = "scroll_to_mark next";
        "kitty_mod+k" = "scroll_to_mark prev";
        "cmd+t" = "new_tab_with_cwd";
        "cmd+enter" = "new_window_with_cwd";
        # Browse scrollback buffer in nvim. Not ctrl+f: Kitty grabs a binding
        # before the running program sees it, and ctrl+f is page-forward in
        # nvim -- the terminal must not shadow a core motion.
        "kitty_mod+f" = "kitty_scrollback_nvim --nvim-args -n";
        "ctrl+j" = "neighboring_window bottom";
        "ctrl+k" = "neighboring_window top";
        "ctrl+h" = "neighboring_window left";
        "ctrl+l" = "neighboring_window right";
        "kitty_mod+t" = "new_tab_with_cwd";
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
        "option+l" = "toggle_layout stack";
        # Browse output of the last shell command in nvim
        "kitty_mod+g" =
          "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
      };
      themeFile = "kanagawa";
    };
  };
}
