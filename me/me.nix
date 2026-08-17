{ pkgs, multiRepoRoot ? "~/anyfin", ... }:
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
}
