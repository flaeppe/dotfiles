{
  description = "Dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, flake-utils, ... }:
    let
      archSystem = "x86_64-linux";
      archPkgs = nixpkgs.legacyPackages.${archSystem};
      archUnstable = import nixpkgs-unstable {
        system = archSystem;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "copilot.vim" ];
      };
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
          ./nvim/nvim.nix
        ];
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unstable = import nixpkgs-unstable {
          inherit system;

          config = {
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [ "copilot.vim" ];
          };
        };
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
              ./nvim/nvim.nix
              ./opencode/opencode.nix
            ];
          };
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.lua-language-server
            pkgs.pyright
            pkgs.ruff
            pkgs.stylua # Formatter for Lua code
          ];
          shellHook = ''
            echo '${luarcJsonContent}' > ./.luarc.json
          '';
        };
      });
}
