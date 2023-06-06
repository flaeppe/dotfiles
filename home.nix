{ config, pkgs, ... }:

{
  home = {
    username = "ludo";
    homeDirectory = "/Users/ludo";
    packages = with pkgs; [
      jq
    ];
    stateVersion = "23.11";
  };

  programs = {
    bat = {
      enable = true;
      config = {
        theme = "OneHalfDarkMod";
        map-syntax = [ ".ignore:.gitignore" ];
      };
    };

    home-manager.enable = true;
  };
}
