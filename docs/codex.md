# Codex configuration

## Global default

The intended global mode is:

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

The durable runtime location is the user-maintained `~/.codex/config.toml`.
[global-defaults.toml](../codex/global-defaults.toml) is the version-controlled
stanza to merge manually at top level. Home Manager does not deploy or merge
this file. Preserve existing trust entries and other runtime settings.
Machine-specific writable roots belong only in the local runtime file.

Sandbox denials return as failures without an escalation approval prompt.
Directory and hook trust remain separate user decisions. These defaults apply
without selecting a profile, subject to higher-precedence project/CLI settings
and managed requirements. The development profile does not override them.

## Home Manager integration

Home Manager links global `AGENTS.md`, hooks, and skills.
`~/.codex/config.toml` remains a regular writable file for runtime
settings and trust decisions. Bare `codex` loads global instructions, skills,
and hooks.

After activation, open `/hooks` in Codex, inspect each command, and trust the
ones you want to run. New or changed definitions require review again. No trust
bypass is configured. The trust dialog offers **Continue without trusting**;
that leaves the hooks inactive.

## Instructions and skills

Global instructions combine the shared Claude instructions with
[Codex conventions](../codex/AGENTS.md). Repository `CLAUDE.md` is a fallback name
in the development profile; `AGENTS.override.md` and `AGENTS.md` take precedence.

Codex 0.153.4 loads global guidance and the Git-root-to-launch-directory chain.
Reading a child file through the shell does not automatically load its nested
instructions. Launch in the directory whose instructions must be present from
the start. When traversing elsewhere, explicitly read the applicable instruction
files before working there; global guidance requests this, but it is model
behavior rather than automatic file discovery. Parent instructions above a Git
root are not included. `AGENTS.md` frontmatter is plain instruction text:
`paths:` does not gate its loading.

`$coding-conventions` routes to the shared Python, TypeScript, Go, Nix, and test
rules. This preserves their content, but selection is skill-driven rather than
Claude's automatic `paths:` loading. `$commit` uses the shared commit skill.
Skill name and description load into the catalog; the body loads on invocation.
Codex skills require `name` and `description` YAML frontmatter. Do not copy
Claude-only invocation, tool, model, agent, or `$ARGUMENTS` semantics blindly.
Codex's explicit-only policy belongs in `agents/openai.yaml` as
`policy.allow_implicit_invocation: false`, not `disable-model-invocation`.

## Compatibility limits

| Feature | Behavior |
|---|---|
| Reasoning | The profile requests `xhigh`; it does not pin a model. Support depends on the selected model. |
| Compaction | `model_auto_compact_token_limit = 400000` requests a token threshold. The model's context limits still apply; this does not enlarge its window or guarantee compaction at exactly that count. |
| Model changes | Global guidance preserves the user's requested model. No verified configuration switch universally forbids fallback; explicit CLI/model selections remain possible. |
| Attribution | Global guidance forbids tool attribution in commits and PRs. No equivalent to Claude's two attribution settings was found in the installed config surface. This is an instruction, not an enforced trailer filter. |
| Footer | Model, directory, session-total input tokens, context-used percentage, in that order. Input totals are cumulative, not current-context token occupancy. Built-in separators, labels, and number formatting differ. |
| Cache and subagents | The status-line picker has no cache item. No separate programmable subagent status-line setting was found. Cache counters in API/exec usage are not a footer replacement. |
| Editing and screen | Vim composer mode and alternate-screen mode are enabled. Alternate screen is Codex's available terminal setting; it does not promise Claude's exact fullscreen layout. |

## Hooks

| Existing behavior | Codex integration |
|---|---|
| Shell guards | Shared `gcloud-command-gate` and `git-local-path-guard` run unchanged; Codex presents shell calls as `Bash` with `tool_input.command`. |
| Edit guards | `patch-adapter.py` maps every patch path, move target, and introduced line to the three shared guards. Deletions also receive protected-path checks. |
| Formatting | The adapter runs the shared formatter and converts its stale-file warning into Codex `PostToolUse` context. |
| Graph augmentation and startup reminder | Not enabled. Shell searches are not Claude `Grep`/`Glob` payloads, and this profile does not register the graph MCP server. The existing reminder script is payload-compatible, but enabling it alone would request unavailable tools. |
| Session lifecycle | Codex has start, end, stop, and prompt-submit hooks. Existing bookkeeping and tab marking depend on Claude's session/history lookup, so they are not installed as silent no-ops. The documented Codex hook events do not include Claude's `Notification`. |

Hook tool coverage is not a complete enforcement boundary. Shell-based file
writes do not become `apply_patch` calls, and later input to an existing shell
session does not rerun `PreToolUse`. The shared guards retain their existing
escape hatches and failure behavior. Hook handlers run outside the agent sandbox
once trusted. Review their code as well as their configured commands.

## Optional automatic approval reviewer

`approvals_reviewer` accepts `user` (the default) or `auto_review`. Automatic
review requires an approval policy that produces eligible requests, such as
`on-request`; `never` produces no escalation requests for it to review.

For an explicitly selected session:

```sh
codex --approve-for-me
```

The corresponding configuration is:

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"
approvals_reviewer = "auto_review"
```

This mode sends eligible approval requests to a separate reviewer agent. It
can approve or deny the requested action; it does not review routine actions
already permitted inside the sandbox. It is not the global default.

No separate reviewer model needs to be configured. `review_model` controls
`/review`, not approval review. A supported approval-review model selector was
not established. Optional `[auto_review].policy` replaces the reviewer policy;
managed `guardian_policy_config` takes precedence. Managed reviewer restrictions
also apply. Automatic review does not grant directory or hook trust.

See [Auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review).

## Useful native workflows

- Use `codex fork` to explore an alternative with the existing history; no new
  wrapper is needed.
- Use `codex review --uncommitted` for a focused local review. Review output is
  advice; retain the repository's tests and human review.
- Use the bundled skill-creator workflow for reusable tasks. Avoid bulk-porting
  Claude skills whose invocation or delegation semantics differ.
- Keep the existing permissions until a concrete second policy needs a named
  profile. `-P` appears on the installed sandbox debug command, not the main
  CLI; don't assume it is a universal launch flag.
- Use app-server RPC for tools that need structured config, hook, or thread
  inspection. Its experimental surface does not justify a new always-running
  service for ordinary interactive development.

## Verification

```sh
python3 -m unittest discover -s codex/tests -v
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  codex/skills/coding-conventions
nix run home-manager -- switch --flake .
```

Stage new files by explicit path before switching; flake evaluation ignores
untracked files. The switch activates the entire Home Manager configuration.

Official references: [profiles](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles),
[instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[hooks and trust](https://learn.chatgpt.com/docs/hooks),
[CLI customization](https://learn.chatgpt.com/docs/cli/slash-commands),
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
