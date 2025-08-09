dotfiles
===

[Install nix](https://nixos.org/download.html#nix-install-macos)

```console
$ sh <(curl -L https://nixos.org/nix/install)
```

[Install home manager](https://nix-community.github.io/home-manager/index.xhtml#ch-installation)

```console
# Install home-manager from e.g. 'release-23.11' branch
$ nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz home-manager
$ nix-channel --update
$ nix-shell '<home-manager>' -A install
```

Enable nix experimental features

```console
mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

Configure dotfiles by running

```console
$ nix run home-manager -- switch --no-write-lock-file --refresh --flake github:flaeppe/dotfiles
```

Setting `fish` as default shell on macOS

1. Append entry for home-manager managed `fish` binary to `/etc/shells`
2. Set default shell with `chsh -s ~/.nix-profile/bin/fish`

Update packages by running

```console
$ nix-channel --update
$ nix flake update
$ nix run home-manager -- switch --refresh --flake path/to/repo
```

Add in an .envrc for local development. There's a devShell declared in flake.nix

```console
use flake

export VIRTUAL_ENV=.venv
layout python
```
