# OpenCode Config (AI-ready)

## Core
- Version: 1.1.21
- Binary: `~/.opencode/bin/opencode`
- Config dir: `~/.config/opencode/`
- Providers: Anthropic (OAuth), GitHub Copilot (OAuth) [OpenAI not configured]
- Default model: `anthropic/claude-opus-4-5`
- Small model: `anthropic/claude-haiku-4-5`

## Agents (markdown at `~/.config/opencode/agent/`)
- build: `github-copilot/gpt-5.1-codex-max` (0.2)
- plan: `anthropic/claude-opus-4-5` (0.05, edit/bash ask)
- code-reviewer: `anthropic/claude-opus-4-5` (0.05, read-only)
- explore/general/research: temp 0.1
- research-deep: `anthropic/claude-opus-4-5` (0.1)
- specialists: typescript/python/golang → `anthropic/claude-sonnet-4-5` (0.2)
- Agents are sourced from markdown; `opencode.json` agent block is empty

## Model Config
- Build: `github-copilot/gpt-5.1-codex-max` (0.2)
- Plan: `anthropic/claude-opus-4-5` (0.05)
- Code review: `anthropic/claude-opus-4-5` (0.05)
- Small tasks: `anthropic/claude-haiku-4-5`
- Providers available: Anthropic, GitHub Copilot (OpenAI not configured)

## Formatters
- Prettier: `npx prettier --write $FILE` (.js/.ts/.jsx/.tsx/.json)
- Ruff: `ruff format $FILE` (.py)
- gofmt: `gofmt -w $FILE` (.go)

## Commands
- /test → run full test suite with coverage
- /review → code review (security/perf/maintainability)

## Permissions
- Deny: `rm -rf /*`, `sudo rm -rf /*`
- Ask: `git push`
- Code-reviewer: no edits; bash limited to git

## Ignore (watcher)
- `node_modules/**`, `dist/**`, `.git/**`, `*.log`, `__pycache__/**`, `.pytest_cache/**`, `vendor/**`

## Usage
- Start: `cd /path/to/project && opencode`
- Switch models: `/model anthropic/claude-sonnet-4-5` or `/model github/copilot`
- Use specialists: `/agent typescript ...`, `/agent python ...`, `/agent golang ...`

## Testing Checklist
- [x] Install/version verified (1.1.21)
- [x] Config dir present
- [x] Main config populated
- [x] Agents created (TS/Python/Go)
- [x] Anthropic OAuth
- [x] GitHub Copilot OAuth

## Troubleshooting
- Formatters: ensure `prettier`, `ruff`, `gofmt` installed and in PATH
- Models: `opencode auth list`; reauth with `opencode auth login [provider]`

## Paths
- Config: `~/.config/opencode/opencode.json`
- Env: `~/.config/opencode/.env`
- Agents: `~/.config/opencode/agent/*.md`
- Auth store: `~/.local/share/opencode/auth.json`

---
Configuration Date: January 15, 2026 | OpenCode Version: 1.1.21
Status: Ready for production use ✅
