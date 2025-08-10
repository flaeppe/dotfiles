{
  # Conditionally used config file (for work repos)
  xdg.configFile."git/work".source = ./work.conf;

  programs = {
    git = {
      enable = true;
      userName = "Petter Friberg";
      userEmail = "3703560+flaeppe@users.noreply.github.com";

      signing = {
        key = "F188F74B056474E8";
        signByDefault = true;
      };

      diff-so-fancy = { enable = true; };

      extraConfig = {
        # Core
        init = { defaultBranch = "main"; };
        pager = { show = "bat"; };
        # Core -- UI
        color = { ui = "auto"; };
        # Core commands -- status
        status = { showStash = true; };
        # Core commands -- network
        push = { default = "simple"; };
        pull = { ff = "only"; };
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
        commit = { verbose = true; };
        tag = { sort = "version:refname"; };
      };

      includes = [{
        condition = "gitdir:~/anyfin/";
        path = "~/.config/git/work";
      }];

      ignores = [
        ".DS_STORE"
        ".venv"
        ".tags"
        ".nvimlog"
        "_private/"
        # direnv, where local project configuration resides
        ".envrc"
        ".direnv/"
        # Directory specific ctags config
        ".ctags.d/"
      ];

      aliases = {
        up = "pull --rebase --autostash";
        slog = "log --pretty=oneline";
        local = "log origin..HEAD --pretty=oneline";
        lg =
          "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        prcheck = ''
          !f() { if [ $# -lt 1 ]; then echo "Usage: git pr <id> [<remote>]  # assuming <remote>[=origin] is on GitHub"; else git checkout -q "$(git rev-parse --verify HEAD)" && git fetch -fv "''${2:-origin}" pull/"$1"/head:pr/"$1" && git checkout pr/"$1"; fi; }; f
        '';
      };
    };
  };
}
