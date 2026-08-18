{
  description = "Dotfiles";

  inputs = {
    # Track the nixpkgs-unstable *channel* rather than the repository's default
    # branch. An unpinned github:nixos/nixpkgs resolves to master, which carries
    # the same package versions but is not a channel: the channel branch only
    # advances once Hydra has built and cached a jobset, so substitutes exist
    # instead of every closure being rebuilt locally.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # A path input copies the working tree of this subdirectory only -- the
    # rest of the state repo (BOARD.md, inbox/, session state) never reaches
    # the world-readable nix store. Untracked files in tools/ still build;
    # promotion to a pinned narHash is a deliberate `nix flake update tools`.
    tools.url = "path:/Users/petter.friberg/anyfin/.me/tools";
  };

  outputs = { nixpkgs, home-manager, flake-utils, tools, ... }:
    let
      # The same nixpkgs, re-imported to permit the unfree packages opted into
      # by name. Modules receive this as `unstable`; it is no longer a newer
      # nixpkgs than `pkgs`, only a less restrictive one.
      unfreePkgs = system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "copilot.vim" ];
        };
      archSystem = "x86_64-linux";
      archPkgs = nixpkgs.legacyPackages.${archSystem};
      archUnstable = unfreePkgs archSystem;
    in {
      # The Linux-personal target deliberately starts small.  It must remain
      # independent of the pass-backed and work-only macOS configuration below.
      homeConfigurations.arch = home-manager.lib.homeManagerConfiguration {
        pkgs = archPkgs;
        extraSpecialArgs = {
          isWork = false;
          unstable = archUnstable;
          multiRepoRoot = "~/repos";
        };
        modules = [
          ./arch.nix
          ./claude/claude.nix
          ./fish/fish.nix
          ./git/git.nix
          ./i3/i3.nix
          ./me/me.nix
          ./nvim/nvim.nix
        ];
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unstable = unfreePkgs system;
        luarcJsonContent = builtins.toJSON {
          diagnostics.globals = [ "vim" ];
          workspace = {
            ignoreDir = [ ".direnv" ".git" ];
            library =
              [ "${pkgs.neovim}/share/nvim/runtime" "$HOME/.config/nvim" ];
          };
        };
      in {
        packages.homeConfigurations."petter.friberg" =
          home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              unstable = unstable;
              isWork = true;
              multiRepoRoot = "~/anyfin";
            };
            modules = [
              ./darwin.nix
              ./claude/claude.nix
              ./fish/fish.nix
              ./git/git.nix
              ./me/me.nix
              ./nvim/nvim.nix
              ./opencode/opencode.nix
              tools.homeModules.default
              ({ config, ... }: {
                # Same value as extraSpecialArgs.multiRepoRoot above; the tools
                # module takes it as a home-manager option instead, since it
                # lives outside dotfiles and can't share that let-binding.
                tools.multiRepoRoot = "~/anyfin";
                tools.kittyAppPath =
                  "${config.home.homeDirectory}/Applications/Home Manager Apps/kitty.app/Contents/MacOS/kitty";
              })
            ];
          };
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.lua-language-server
            pkgs.nodejs # Runtime pyright executes on
            pkgs.python3 # Interpreter uv builds the tool environment against
            pkgs.stylua # Formatter for Lua code
            pkgs.uv
          ];
          # ruff and pyright come from pyproject.toml, which is also where their
          # configuration lives, so there is one pinned version of each rather
          # than a nixpkgs copy and a locked copy that drift. Editor LSPs resolve
          # them by name, hence the venv on PATH.
          shellHook = ''
            echo '${luarcJsonContent}' > ./.luarc.json
            uv sync --quiet
            PATH="$PWD/.venv/bin:$PATH"
            # git hooks are not tracked, so a fresh checkout has none until this
            # runs. Idempotent.
            uv run pre-commit install > /dev/null
          '';
        };
      });
}
