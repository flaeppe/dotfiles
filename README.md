dotfiles
===

[Install nix](https://nixos.org/download.html#nix-install-macos)

```bash
sh <(curl -L https://nixos.org/nix/install)
```

Enable nix experimental features

```bash
mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

Configure dotfiles by running

```bash
nix run home-manager -- switch --no-write-lock-file --refresh --flake github:flaeppe/dotfiles
```

Setting `fish` as default shell on macOS (optional as kitty terminal sets fish as default shell)

1. Append entry for home-manager managed `fish` binary to `/etc/shells`
2. Set default shell with `chsh -s ~/.nix-profile/bin/fish`

Update packages by running

```bash
nix flake update
nix run home-manager -- switch --refresh --flake path/to/repo
```

Add in an .envrc for local development. There's a devShell declared in flake.nix

```bash
use flake

export VIRTUAL_ENV=.venv
layout python
```

Entering the shell syncs the tool environment from `pyproject.toml` and installs the
git hooks. ruff lints and formats the Python on commit; pyright is kept off the
commit path and runs over everything on request:

```bash
pre-commit run --all-files --hook-stage manual pyright
```

## Documentation

- [Local PR review](docs/pr-review.md) — reviewing a pull request in the editor, with
  findings delivered as a stack of commits rather than comments.

## Secrets

Secrets are managed by [pass](https://www.passwordstore.org/) (GPG-encrypted, git-synced).
The claude wrapper script reads secrets from `pass` at launch. Home Manager
activation scripts write `~/.sentryclirc` from `pass` on `home-manager switch`.
