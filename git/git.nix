{
  # Conditionally used config file (for work repos)
  xdg.configFile."git/work".source = ./work.conf;

  programs = {
    git = {
      enable = true;
      userName = "Petter Friberg";
      userEmail = "petter_friberg@hotmail.com";

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

      includes = [
        {
          condition = "gitdir:~/anyfin/";
          path = "~/.config/git/work";
        }
      ];

      ignores = [
        ".DS_STORE"
        ".venv"
        ".tags"
        ".nvimlog"
        "_private/"
        # direnv, where local project configuration resides
        ".envrc"
        ".direnv/"
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
        recentb = ''
          !r() { refbranch=$1 count=$2; git for-each-ref --sort=-committerdate refs/heads --format='%(refname:short)|%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:blue)%(subject)|%(color:magenta)%(authorname)%(color:reset)' --color=always --count=''${count:-20} | while read line; do branch=$(echo "$line" | awk 'BEGIN { FS = "|" }; { print $1 }' | tr -d '*'); ahead=$(git rev-list --count "''${refbranch:-origin/master}..''${branch}"); behind=$(git rev-list --count "''${branch}..''${refbranch:-origin/master}"); colorline=$(echo "$line" | sed 's/^[^|]*|//'); echo "$ahead|$behind|$colorline" | awk -F'|' -v OFS='|' '{$5=substr($5,1,70)}1' ; done | ( echo "ahead|behind||branch|lastcommit|message|author\n" && cat) | column -ts'|';}; r'';
        oldestb =
          "for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(color:magenta)%(authorname)%(color:reset) (%(color:green)%(committerdate:relative)%(color:reset))'";
      };
    };
  };
}
