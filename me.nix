# Background timers for the `me` CLI, plus the Codex quota-window poke.
#
# The `me` binary is installed to ~/.local/bin by its own build, not by
# home-manager, so these agents name it by path rather than by store path.
# Nothing else here depends on it: if the file is absent the jobs no-op every
# 15 minutes instead of failing at build time.
{ pkgs, lib, config, ... }:

let
  me = "${config.home.homeDirectory}/.local/bin/me";

  # launchd gives a job a bare-bones PATH (/usr/bin:/bin:/usr/sbin:/sbin) and
  # inherits nothing from an interactive shell. The `me`/`prs` jobs run gh,
  # fish and git by bare name: git survives on macOS's /usr/bin/git, gh
  # exists only in the nix profile and is otherwise "not found in $PATH".
  # ~/.local/bin carries `codex` and `me` themselves, needed by name inside
  # codex-daily-poke.sh's own subprocess (`sam usage codex` shells out to
  # `codex app-server` by bare name).
  launchdPath =
    "${config.home.homeDirectory}/.local/bin:${config.home.homeDirectory}/.nix-profile/bin:/usr/bin:/bin:/usr/sbin:/sbin";
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

  # Fires once a day; the command throttles itself to a real 14-day cadence
  # via a persisted timestamp, same self-throttle shape as me-prs-sweep/
  # me-pulse above but on a much longer cycle, since it drives a real Codex
  # turn (cost, not just a cheap local scan) rather than a background scan.
  # StartCalendarInterval, not StartInterval: a fixed daily check-in beats
  # the review firing at an arbitrary clock time depending on when the
  # machine last woke, and 06:30 sits ahead of codex-daily-poke's 07:00 so
  # the two don't contend for the day's first quota window.
  launchd.agents.me-outside-review = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ me "outside-review" ];
      StartCalendarInterval = [{
        Hour = 6;
        Minute = 30;
      }];
      RunAtLoad = false;
      EnvironmentVariables.PATH = launchdPath;
    };
  };

  # Hourly sweep of a Gmail label into a private automation repo; see that
  # repo for what it does and why -- this file only names where it lives.
  # Same shape as me-prs-sweep/me-pulse above, except the target script isn't
  # under this repo (it's private, no remote): resolve it at runtime from
  # ~/.config/me-home, the same machine-local, uncommitted indirection
  # codex-daily-poke.sh's SAM_DIR already uses, so the repo name never has to
  # appear in this public repo.
  launchd.agents.composer-sweep = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''exec "$(cat "$HOME/.config/me-home")/scripts/composer-sweep"''
      ];
      StartInterval = 3600; # hourly
      RunAtLoad = false;
      EnvironmentVariables.PATH = launchdPath;
    };
  };

  # Fires one cheap real Codex turn at 07:00 so the day's ~5h quota windows
  # land at roughly 07-12-17-22 instead of wherever the day's first
  # incidental Codex use happens to fall (Petter, 2026-09-10; see
  # me/quota-calibration.md in the plan tree). A window activates only on a real
  # completed turn, never on a quota read, so this has to be an actual turn,
  # not a status check. codex-daily-poke.sh checks the turn's own exit code
  # and then asserts the primary window really did land ~5h out; either
  # failure goes through `me note`, the channel `me brief`/`me pulse` surface
  # -- see the script for why (inbox/hook-errors.log is where the PR sweep's
  # failures go silent).
  #
  # StartCalendarInterval, not StartInterval: a fixed 07:00, not "every N
  # seconds". If the machine is asleep at 07:00, launchd runs it on wake
  # (coalesced into one run, not one per missed interval -- man
  # launchd.plist); if the machine is off at 07:00, it runs at next
  # boot/login instead, which can land after Petter's own first Codex use
  # of the day and miss the alignment that run was for.
  launchd.agents.codex-daily-poke = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${./scripts/codex-daily-poke.sh}"
        "${./scripts/codex-primary-window-check.py}"
      ];
      StartCalendarInterval = [{
        Hour = 7;
        Minute = 0;
      }];
      RunAtLoad = false;
      EnvironmentVariables.PATH = launchdPath;
    };
  };
}
