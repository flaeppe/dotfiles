# Bounds the Go build cache: every 6 hours, delete entries unused for 24 hours.
#
# The script is a store copy run by /bin/sh, and launchd's bare PATH
# (/usr/bin:/bin) already holds every tool it calls (find, du, cut, wc).
{ pkgs, lib, config, ... }:

let
  logDir = "${config.home.homeDirectory}/Library/Logs";
in {
  # `launchd.agents` is declared on every platform but only takes effect on
  # darwin; mkIf keeps this an inert attribute set elsewhere.
  launchd.agents.go-cache-trim = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "/bin/sh" "${./go-cache-trim.sh}" ];
      StartInterval = 21600; # 6 hours
      RunAtLoad = false;
      StandardOutPath = "${logDir}/go-cache-trim.log";
      StandardErrorPath = "${logDir}/go-cache-trim.err.log";
      EnvironmentVariables.PATH = "/usr/bin:/bin";
    };
  };
}
