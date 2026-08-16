{ pkgs, ... }: {
  # Fuzzy find Git branches with advanced preview and actions. It needs more than a
  # simple function so we manually declare the config file.
  xdg.configFile."fish/functions/gb.fish".source =
    ./functions/git-branches.fish;
  # Fuzzy find Git hashes with preview and actions. It needs more than a simple function
  # so we manually declared the config file.
  xdg.configFile."fish/functions/flog.fish".source = ./functions/flog.fish;
  # Completions are a file rather than a function, and `programs.fish` has nowhere to put
  # one, so it is placed directly.
  xdg.configFile."fish/completions/wt.fish".source = ./completions/wt.fish;

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
        # Fuzzy pickers for paths, history and git. Its Search Directory reads
        # the token under the cursor: with the cursor after `some/dir/` it
        # searches recursively inside that directory instead of from $PWD.
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
      ];
      shellAliases = { ls = "ls -h --color=auto"; };
      shellInit = ''
        # Disable fish greeting
        set fish_greeting
        # Prompt colours are declared here instead of relying on Fish's
        # per-machine universal variables, keeping Darwin and Arch identical.
        set -g fish_color_user brgreen
        set -g fish_color_host normal
        set -g fish_color_cwd green
        set -g fish_color_error brred
        # Disable 'activate.fish' auto setting and displaying fish status
        set -x VIRTUAL_ENV_DISABLE_PROMPT 1
        # /usr/local/bin is not sourced by fish via path_helper; add it at low priority
        # so tools like OrbStack's docker are available without overriding Nix binaries
        fish_add_path --append /usr/local/bin
      '';
      interactiveShellInit = ''
        # TODO remove when https://github.com/NixOS/nixpkgs/issues/462025 gets resolved
        set -p fish_complete_path ${pkgs.fish}/share/fish/completions

        # Keep hidden files (.envrc, .github) in the picker but drop .git's contents.
        set -g fzf_fd_opts --hidden --exclude .git

        # Ctrl-only bindings, overriding the plugin's ctrl-alt-* defaults: on a
        # Swedish Mac layout Alt is a character modifier (Alt+7 |, Alt+8 [,
        # Alt+9 ], Alt+2 @), so it cannot be used for key bindings. ctrl-h/j/k/l
        # are excluded because Kitty consumes them for window navigation before
        # fish sees them; ctrl-s is fish's pager search and ctrl-p is up-line.
        fzf_configure_bindings --directory=ctrl-t --history=ctrl-r --git_status=ctrl-g --git_log=ctrl-o --processes= --variables=
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
        new-session = {
          description =
            "Opens a new, independent Kitty window for a specific session file";
          body = ''
            ${builtins.readFile ./functions/new-session.fish}
          '';
        };
        review = {
          description =
            "Sets up a two-worktree review session for a GitHub PR and opens it in Kitty";
          body = ''
            ${builtins.readFile ./functions/review.fish}
          '';
        };
        # Reached through `review list`, `review retire` and `review skim`, which is the one
        # entry point worth remembering; these carry the bodies so that dispatcher stays
        # readable.
        _review_list = {
          description = "Lists every review session in this repository, live or retired";
          body = ''
            ${builtins.readFile ./functions/_review_list.fish}
          '';
        };
        _review_retire = {
          description =
            "Archives a review session's findings and suggestions, then removes its worktrees";
          body = ''
            ${builtins.readFile ./functions/_review_retire.fish}
          '';
        };
        _review_skim = {
          description =
            "Opens the read-only skim worktree for browsing pull requests across the org";
          body = ''
            ${builtins.readFile ./functions/_review_skim.fish}
          '';
        };
        wt = {
          description =
            "Lists every worktree with what it would cost to delete it, oldest first";
          body = ''
            ${builtins.readFile ./functions/worktrees.fish}
          '';
        };
        _wt_repo = {
          description = "Renders one repository's worktrees for `wt`";
          body = ''
            ${builtins.readFile ./functions/_wt_repo.fish}
          '';
        };
        _wt_new = {
          description = "Creates a worktree in .worktrees/ and prepares it for editing";
          body = ''
            ${builtins.readFile ./functions/_wt_new.fish}
          '';
        };
        _wt_rm = {
          description =
            "Removes worktrees that hold no unsaved work, and the branches they finished";
          body = ''
            ${builtins.readFile ./functions/_wt_rm.fish}
          '';
        };
        # Shared by the listing and the remover, so that what `wt` calls removable and what
        # `wt rm` agrees to remove cannot drift apart.
        _wt_verdict = {
          description = "Reports what a worktree's git state says about removing it";
          body = ''
            ${builtins.readFile ./functions/_wt_verdict.fish}
          '';
        };
        _wt_trees = {
          description = "Reassembles `git worktree list --porcelain` into one record a line";
          body = ''
            ${builtins.readFile ./functions/_wt_trees.fish}
          '';
        };
        _wt_owner = {
          description = "Names the tool a worktree belongs to, if any";
          body = ''
            ${builtins.readFile ./functions/_wt_owner.fish}
          '';
        };
        _wt_candidates = {
          description = "Lists the worktrees `wt rm` will consider, for completion";
          body = ''
            ${builtins.readFile ./functions/_wt_candidates.fish}
          '';
        };
        _wt_age = {
          description = "Formats a unix timestamp as a short age";
          body = ''
            ${builtins.readFile ./functions/_wt_age.fish}
          '';
        };
        # Shared by `review <pr>` and `review skim`: both must prepare a worktree
        # identically, or a language server works in one surface and not the next.
        _review_prepare_tree = {
          description = "Copies local config, links dependency trees and runs .review/setup in a worktree";
          body = ''
            ${builtins.readFile ./functions/_review_prepare_tree.fish}
          '';
        };
      };
    };
  };
}
