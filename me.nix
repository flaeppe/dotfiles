# Two background timers for the `me` CLI.
#
# The binary is installed to ~/.local/bin by its own build, not by
# home-manager, so these agents name it by path rather than by store path.
# Nothing else here depends on it: if the file is absent the jobs no-op every
# 15 minutes instead of failing at build time.
{ pkgs, lib, config, ... }:

let
  me = "${config.home.homeDirectory}/.local/bin/me";

  # launchd gives a job a bare-bones PATH (/usr/bin:/bin:/usr/sbin:/sbin) and
  # inherits nothing from an interactive shell. Both jobs run gh, fish and git
  # by bare name: git survives on macOS's /usr/bin/git, gh exists only in the
  # nix profile and is otherwise "not found in $PATH".
  launchdPath =
    "${config.home.homeDirectory}/.nix-profile/bin:/usr/bin:/bin:/usr/sbin:/sbin";
in {
  # Fires unconditionally; the command throttles itself on wall-clock hour and
  # a persisted timestamp, so most invocations are a cheap no-op. It also
  # records its own failures where it expects them read, hence no
  # StandardOutPath/StandardErrorPath.
  #
  # `launchd.agents` is declared on every platform but only takes effect when
  # `launchd.enable` is true (default: darwin only); mkIf keeps this an inert
  # attribute set on Linux rather than trusting that default.
  launchd.agents.me-prs-sweep = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ me "prs" "sweep" ];
      StartInterval = 900; # 15 minutes
      RunAtLoad = false;
      EnvironmentVariables.PATH = launchdPath;
    };
  };

  # Same shape and same self-throttling as me-prs-sweep above.
  launchd.agents.me-pulse = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ me "pulse" ];
      StartInterval = 900; # 15 minutes
      RunAtLoad = false;
      EnvironmentVariables.PATH = launchdPath;
    };
  };
}
