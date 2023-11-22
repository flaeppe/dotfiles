dotfiles
===

[Install nix](https://nixos.org/download.html#nix-install-macos)

```console
$ sh <(curl -L https://nixos.org/nix/install)
```

[Install home manager](https://nix-community.github.io/home-manager/index.html#sec-install-standalone)

```console
# Install home-manager from 'master' branch ('release-*' are also available)
$ nix-channel --add https://github.com/nix-community/home-manager/archive/refs/heads/master.tar.gz home-manager
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
$ nix run home-manager/master -- switch --no-write-lock-file --refresh --flake github:flaeppe/dotfiles
```

Setting `fish` as default shell on macOS

1. Append entry for home-manager managed `fish` binary to `/etc/shells`
2. Set default shell with `chsh -s ~/.nix-profile/bin/fish`
