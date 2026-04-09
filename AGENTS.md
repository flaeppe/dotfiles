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
- `fish/` — Fish shell configuration (module imported via `fish/fish.nix`)
- `git/` — Git configuration (module imported via `git/git.nix`)
- `nvim/` — Neovim configuration (module imported via `nvim/nvim.nix`)
- `gnupg/` — GPG agent configuration
- `node-packages/` — Node packages built with node2nix
- `opencode/` — OpenCode configuration (module imported via `opencode/opencode.nix`)
  - `opencode.json` — Main OpenCode config (providers, MCP servers, permissions, formatters)
  - `tui.json` — TUI theme/layout config
  - `agent/` — Custom agent definitions (plan, build, code-reviewer, etc.)
  - `command/` — OpenCode-specific slash commands (with agent routing)
  - `skills/` — **Shared** language/framework skills used by BOTH OpenCode and Claude Code
  - `AGENTS.md` — **Shared** global instructions used by BOTH OpenCode and Claude Code
- `claude/` — Claude Code configuration (module imported via `claude/claude.nix`)
  - `settings.json` — Claude Code settings (model, permissions, MCP servers)
  - `skills/` — Claude-specific workflow commands (plan, explore, pr, review, etc.)
  - `claude.nix` — Home Manager module that deploys shared + Claude-specific config
- `scripts/` — Activation scripts run by Home Manager
  - `pass-to-file.sh` — Helper to write secrets from `pass` to files
  - `write-sentryclirc.sh` — Writes `.sentryclirc` from `pass`

## OpenCode + Claude Code Shared Configuration

OpenCode and Claude Code share configuration via symlinks managed by Home Manager.
Understand what's shared and what's tool-specific before making changes.

### Shared (edit once, both tools get it)

| File/Directory | Deployed as (OpenCode) | Deployed as (Claude Code) |
|---|---|---|
| `opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` | `~/.claude/CLAUDE.md` |
| `opencode/skills/` (with `paths`) | `~/.config/opencode/skills/` | `~/.claude/rules/` (auto-loaded by file type) |
| `opencode/skills/` (without `paths`) | `~/.config/opencode/skills/` | `~/.claude/skills/` (user-invocable) |

**When editing global instructions or language/framework skills, always edit the
source in `opencode/` — both tools pick up the change on `home-manager switch`.**

Skills with a `paths` field become auto-loaded rules in Claude Code (loaded when
matching files are read). Skills without `paths` (commit, planning, general) stay
as user-invocable skills in Claude Code.

Frontmatter includes fields for both tools (`user-invocable`, `paths`). Each tool
ignores the fields it doesn't understand. Do not remove any frontmatter fields.

### Tool-specific (separate files)

| OpenCode only | Claude Code only |
|---|---|
| `opencode/opencode.json` (providers, formatters) | `claude/settings.json` (permissions, MCP) |
| `opencode/agent/` (agent definitions with model routing) | — |
| `opencode/command/` (commands with agent routing) | `claude/skills/` (workflow commands) |
| `opencode/tui.json` | — |

### Workflow commands exist in both tools

The 8 workflow commands (`plan`, `explore`, `pr`, `pr-playbook`, `fix-pr`,
`research`, `review`, `run-tests`/`test`) have separate implementations because
the format differs (OpenCode uses agent routing and subtask mode, Claude Code
uses SKILL.md frontmatter). When changing the intent or instructions of a
workflow command, update both:
- `opencode/command/<name>.md`
- `claude/skills/<name>/SKILL.md`

### Adding a new shared skill

1. Create `opencode/skills/<name>/SKILL.md` with `user-invocable: true` in frontmatter
2. If it's language/file-type-specific: add `paths` to frontmatter and add the
   name to `sharedRules` in `claude/claude.nix` (auto-loaded as a rule)
3. If it's a general workflow skill: add the name to `sharedSkills` in
   `claude/claude.nix` (user-invocable)
4. Run `home-manager switch`

### MCP servers and permissions

MCP servers and bash permissions are configured separately per tool:
- OpenCode: `opencode/opencode.json` (under `mcp` and `permission` keys)
- Claude Code: `claude/settings.json` (under `mcpServers` and `permissions` keys)

When adding a new MCP server or permission rule, update both files.

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
