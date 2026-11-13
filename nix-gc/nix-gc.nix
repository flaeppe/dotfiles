# Daily Nix garbage collection: deletes the user's profile generations older
# than 7 days, then every store path nothing references.
#
# Home Manager's `nix.gc` module is not used: on darwin it passes `options` as a
# single argv element, so "--delete-older-than 7d" reaches nix-collect-garbage
# as one unrecognised flag.
{ pkgs, lib, config, ... }:

let
  logDir = "${config.home.homeDirectory}/Library/Logs";
in {
  # `launchd.agents` is declared on every platform but only takes effect on
  # darwin; mkIf keeps this an inert attribute set elsewhere.
  launchd.agents.nix-gc = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.nix}/bin/nix-collect-garbage"
        "--delete-older-than"
        "7d"
      ];
      # launchd runs a calendar job missed during sleep at the next wake.
      StartCalendarInterval = [{ Hour = 3; Minute = 15; }];
      RunAtLoad = false;
      StandardOutPath = "${logDir}/nix-gc.log";
      StandardErrorPath = "${logDir}/nix-gc.err.log";
    };
  };
}
