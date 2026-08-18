{ pkgs, ... }:
let
  glog = pkgs.buildGoModule {
    pname = "glog";
    version = "0.1.0";
    src = ./.;
    vendorHash = "sha256-cGZP4BZDkTYwhiV+aMQIXNYgvlvLPyP0Q4iJhmmIxBM=";
  };
in {
  # Same stable-path convention as ../me/me.nix's home.file entry.
  home.file.".local/bin/glog".source = "${glog}/bin/glog";
}
