dotfiles
===

[Install nix](https://nixos.org/download.html#nix-install-macos)

```console
$ sh <(curl -L https://nixos.org/nix/install)
```

[Install home manager](https://nix-community.github.io/home-manager/index.html#sec-install-standalone)

```console
$ nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
$ nix-channel --update
$ nix-shell '<home-manager>' -A install
```

Configure dotfiles by running

```console
$ nix run home-manager/master -- switch --flake ~/.dotfiles#ludo
```
