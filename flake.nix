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
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.homeConfigurations = {
          "petter.friberg" = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              mac-app-util.homeManagerModules.default
              ./home.nix
            ];
          };
        };
      });
}
