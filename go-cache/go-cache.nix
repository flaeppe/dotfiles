# Bounds the Go build cache: every hour, delete entries unused for 24 hours,
# then the least-recently-used entries until the cache is under 10 GB.
#
# The script is a store copy run by /bin/sh, and launchd's bare PATH
# (/usr/bin:/bin) already holds every tool it calls (find, stat, sort, du,
# cut, wc).
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
      StartInterval = 3600; # 1 hour; a busy day outgrows the size cap within hours
      RunAtLoad = false;
      StandardOutPath = "${logDir}/go-cache-trim.log";
      StandardErrorPath = "${logDir}/go-cache-trim.err.log";
      EnvironmentVariables.PATH = "/usr/bin:/bin";
    };
  };
}
