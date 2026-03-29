---
name: nix
description: Use when editing Nix code or flakes - covers flake structure, derivations, and module patterns
---

# Nix Guidelines

## Working in Existing Codebases

- Write new code correctly (pure, explicit inputs); don't refactor old modules unless asked
- Avoid spreading ad-hoc imperative shells; keep new logic pure/structured
- Prefer adding new overlays/modules over patching scattered overrides

## Flake Basics

```nix
{
  description = "example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.hello;
        devShells.default = pkgs.mkShell { buildInputs = [ pkgs.hello ]; };
      }
    );
}
```

## Derivation Basics

```nix
{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "tool";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];
}
```

**Rules:**
- `nativeBuildInputs` for build-time tools; `buildInputs` for target deps
- Use `passthru.tests` for simple checks

## Overlays and Overrides

```nix
final: prev: {
  my-hello = prev.hello.overrideAttrs (old: {
    pname = "my-hello";
    version = "0.2.0";
  });
}
```

Prefer overlays for repo-wide tweaks; prefer `overrideAttrs` over `fetchpatch` unless necessary.

## Modules (NixOS/Home Manager)

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.example;
in {
  options.services.example.enable = lib.mkEnableOption "Example service";

  config = lib.mkIf cfg.enable {
    systemd.services.example = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.hello}/bin/hello";
    };
  };
}
```

**Rules:**
- Options live under `options`; behavior under `config`
- Gate behavior with `mkIf cfg.enable`
- Use `mkDefault`/`mkOverride` when merging priorities matter

## Quick Reference

| Prefer | Over |
|--------|------|
| Flakes with pinned inputs | Ad-hoc channel pinning |
| Overlays/overrideAttrs | Forking nixpkgs for small tweaks |
| `nativeBuildInputs` for build tools | Putting everything in `buildInputs` |
| `mkIf` with options | Free-form conditionals in config |
| Pure functions `{ pkgs }:` | Implicit global `pkgs` |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `buildInputs` for compilers | Put toolchains in `nativeBuildInputs` |
| Mixing options/config | Define options separately, gate config with `mkIf` |
| Implicit `pkgs` | Pass `pkgs` explicitly; avoid hidden imports |
| No pin on nixpkgs | Pin via flake input |
