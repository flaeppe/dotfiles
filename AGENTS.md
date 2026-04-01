# Development Guidelines

This is a personal dotfiles repository managed with Nix flakes and Home Manager.
Changes here directly affect the user's development environment — exercise caution
and verify thoroughly before applying.

Building locally applies changes immediately to the local environment. This means
mistakes are instantly live. However, this shouldn't be a major concern as rolling
back to a previous Home Manager generation is always available.

## Prerequisites

Load the `nix` skill before making any changes. This is mandatory, no exceptions.

## Repository Structure

- `flake.nix` — Flake definition with Home Manager configuration
- `fish/` — Fish shell configuration (module imported via `fish/fish.nix`)
- `git/` — Git configuration (module imported via `git/git.nix`)
- `nvim/` — Neovim configuration (module imported via `nvim/nvim.nix`)
- `gnupg/` — GPG agent configuration
- `node-packages/` — Node packages built with node2nix
- `opencode/` — OpenCode configuration (module imported via `opencode/opencode.nix`)
  - `opencode.json` — Main OpenCode config (providers, MCP servers, permissions, formatters)
  - `tui.json` — TUI theme/layout config
  - `agent/` — Custom agent definitions (plan, build, code-reviewer, etc.)
  - `command/` — Custom slash commands
  - `skills/` — Agent skills (commit, golang, nix, python, typescript, etc.)
  - `AGENTS.md` — Global instructions loaded by OpenCode in every session
- `scripts/` — Activation scripts run by Home Manager
  - `pass-to-file.sh` — Helper to write secrets from `pass` to files
  - `write-sentryclirc.sh` — Writes `.sentryclirc` from `pass`

## Secrets Management

Secrets are managed via `pass` and written to disk during `home-manager switch` via activation scripts in `flake.nix`. Some secrets are also injected into wrapper scripts at launch time.

## Linting and Formatting

- **Format Nix files:** `nix fmt .`
- **Validate flake configuration:** `nix flake check`

## Testing

There is no explicit test framework. This is a configuration repository — testing
means verifying that the Home Manager configuration builds successfully:

```bash
nix run home-manager -- switch --flake .
```

## Safety

This is a personal dotfiles repo. Changes affect the user's live development
environment. Exercise extra caution:

- Always verify changes build before committing
- Test configuration changes locally before pushing
- Be especially careful with shell configuration, PATH modifications, and
  environment variables — mistakes can break the user's terminal
