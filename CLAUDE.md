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

Home Manager symlinks these files into `~/.config/` and `~/.local/` — this repo is the source of truth, not the symlink targets.

- `flake.nix` — Flake definition with Home Manager configuration
- `docs/` — Feature documentation for workflows spanning several programs
  - `pr-review.md` — the local PR review tooling (nvim + fish + the `pr-session` skill)
- `fish/` — Fish shell configuration (module imported via `fish/fish.nix`)
- `git/` — Git configuration (module imported via `git/git.nix`)
- `nvim/` — Neovim configuration (module imported via `nvim/nvim.nix`)
- `gnupg/` — GPG agent configuration
- `node-packages/` — Node packages built with node2nix
- `claude/` — Claude Code configuration (module imported via `claude/claude.nix`)
  - `CLAUDE.md` — Global instructions, deployed to `~/.claude/CLAUDE.md`
  - `settings.json` — Claude Code settings (model, permissions, hooks)
  - `rules/` — Language/framework rules, each gated by `paths:` frontmatter
  - `skills/` — Workflow skills, loaded on invocation
  - `agents/` — Subagent definitions dispatchable via the Agent tool
  - `commands/` — Slash commands
  - `hooks/` — PreToolUse/PostToolUse guards, installed as executable copies
  - `claude.nix` — Home Manager module that deploys all of the above
- `scripts/` — Activation scripts run by Home Manager
  - `pass-to-file.sh` — Helper to write secrets from `pass` to files
  - `write-sentryclirc.sh` — Writes `.sentryclirc` from `pass`

## Where a Claude Code file goes

The directory decides how Claude Code loads a file, so placement is the only
decision — `claude/claude.nix` deploys each directory wholesale and has no list to
keep in sync.

| Put it in | Loaded |
|---|---|
| `claude/CLAUDE.md` | every session |
| `claude/rules/<name>.md` | when a session touches a file matching its `paths:` frontmatter |
| `claude/skills/<name>/SKILL.md` | on `/<name>`, or when Claude judges it relevant |
| `claude/agents/<name>.md` | on dispatch through the Agent tool, in its own context |
| `claude/commands/<name>.md` | on `/<name>` |

A rule without `paths:` loads unconditionally, which is what `CLAUDE.md` is for —
add the frontmatter or put the file elsewhere.

Adding one is: create the file, `nix run home-manager -- switch --flake .`. Nothing
else. The deployed paths are nix-store symlinks, so nothing appears before
activation.

## Secrets Management

Secrets are managed via `pass` and written to disk during `home-manager switch` via activation scripts in `flake.nix`. Some secrets are also injected into wrapper scripts at launch time.

## Linting and Formatting

Nix files are formatted by hand — `flake.nix` defines no `formatter` output, so
`nix fmt` does not work in this repo. `nix flake check` currently fails on
`packages.homeConfigurations` not being a derivation (`flake.nix:63`), independent
of any change; the build below is the real gate.

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
