{ pkgs, lib, multiRepoRoot ? "~/anyfin", ... }:
let
  # Compiled so the tool depends on no ambient interpreter version; the state
  # root default is baked in per host from the same multiRepoRoot the rendered
  # skills use. $ME_HOME still overrides at runtime.
  me = pkgs.buildGoModule {
    pname = "me";
    version = "0.1.0";
    src = ./.;
    vendorHash = null;
    ldflags = [ "-X" "main.defaultMeHome=${multiRepoRoot}/.me" ];
  };
in {
  # The stable absolute path the session-end hook shim references.
  home.file.".local/bin/me".source = "${me}/bin/me";

  # Fires unconditionally every 15 minutes; `me prs sweep` decides internally
  # (wall-clock hour + a persisted timestamp) whether there's anything to do,
  # so a needless invocation is a cheap no-op. `launchd.agents` is declared
  # by home-manager on every platform, but only takes effect when
  # `launchd.enable` is true, which defaults to `pkgs.stdenv.isDarwin` -- the
  # mkIf below keeps this a no-op attribute set on Linux rather than relying
  # on that default alone. No StandardOutPath/StandardErrorPath: `me prs
  # sweep` already logs its own failures to inbox/hook-errors.log via
  # hookError(), so a second logging path here would just be redundant.
  launchd.agents.me-prs-sweep = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${me}/bin/me" "prs" "sweep" ];
      StartInterval = 900; # 15 minutes
      RunAtLoad = false;
    };
  };

  # Same shape, same reasoning as me-prs-sweep above -- `me pulse` self-throttles.
  launchd.agents.me-pulse = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${me}/bin/me" "pulse" ];
      StartInterval = 900; # 15 minutes
      RunAtLoad = false;
    };
  };
}
