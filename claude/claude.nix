{ pkgs, lib, unstable, ... }:
let
  opencode = ../opencode;

  # MCP binary from nixpkgs-unstable; tracks the channel on `nix flake update`.
  # Provides only the executable -- the discovery hook + skill are wired below.
  # Do NOT run `codebase-memory-mcp install`/`update`: it mutates ~/.claude
  # (hooks, settings.json, skills) which this flake owns and would revert.
  inherit (unstable) codebase-memory-mcp;

  # Rules shared with OpenCode -- auto-loaded by paths in Claude Code
  # (single source in opencode/skills/, deployed as ~/.claude/rules/)
  sharedRules = [
    "golang"
    "golang-test"
    "jest"
    "nix"
    "pytest"
    "python"
    "test"
    "typescript"
    "vitest"
  ];

  # Always-loaded rules (no paths = loaded in every session, like CLAUDE.md)
  alwaysRules = [ ];

  # Skills shared with OpenCode -- user-invocable in Claude Code
  # (single source in opencode/skills/, deployed as ~/.claude/skills/)
  # `commit` is a skill here (loaded on demand when committing, e.g. via the
  # commit-msg wrapper), not an always-rule.
  sharedSkills = [
    "commit"
    "general"
    "planning"
    "docs-expert"
    "deps-expert"
    "correlation-expert"
    "simplicity-expert"
  ];

  # Claude subagents -- thin wrappers that load the matching skill, dispatchable
  # in their own context via the Agent tool (single source stays in the skill).
  claudeAgents = [ "docs-expert" "correlation-expert" "deps-expert" "simplicity-expert" ];

  claudeAgentEntries = builtins.listToAttrs (map (name: {
    name = ".claude/agents/${name}.md";
    value = { source = ./agents + "/${name}.md"; };
  }) claudeAgents);

  sharedRuleEntries = builtins.listToAttrs (map (name: {
    name = ".claude/rules/${name}.md";
    value = { source = "${opencode}/skills/${name}/SKILL.md"; };
  }) sharedRules);

  alwaysRuleEntries = builtins.listToAttrs (map (name: {
    name = ".claude/rules/${name}.md";
    value = { source = "${opencode}/skills/${name}/SKILL.md"; };
  }) alwaysRules);

  sharedSkillEntries = builtins.listToAttrs (map (name: {
    name = ".claude/skills/${name}";
    value = {
      source = "${opencode}/skills/${name}";
      recursive = true;
    };
  }) sharedSkills);
in {
  # npx, for `ccusage` (statusline session-spend reporting) -- no first-party
  # `claude usage` CLI exists yet.
  home.packages = [ pkgs.nodejs ];

  home.file = sharedRuleEntries // alwaysRuleEntries // sharedSkillEntries
    // claudeAgentEntries // {
    # Global instructions -- shared, single source in opencode/AGENTS.md
    ".claude/CLAUDE.md".source = "${opencode}/AGENTS.md";

    ".claude/commands/delegate.md".source = ./commands/delegate.md;

    # Claude-specific workflow commands
    ".claude/skills/explore".source = ./skills/explore;
    ".claude/skills/pr".source = ./skills/pr;
    ".claude/skills/pr-playbook".source = ./skills/pr-playbook;
    ".claude/skills/pr-session".source = ./skills/pr-session;
    ".claude/skills/fix-pr".source = ./skills/fix-pr;
    ".claude/skills/research".source = ./skills/research;
    ".claude/skills/pr-review".source = ./skills/pr-review;
    ".claude/skills/run-tests".source = ./skills/run-tests;
    ".claude/skills/codebase-memory".source = ./skills/codebase-memory;
    ".claude/skills/test-expert".source = ./skills/test-expert;
    ".claude/skills/commit-msg".source = ./skills/commit-msg;
    ".claude/skills/analyze".source = ./skills/analyze;
    ".claude/skills/prompt".source = ./skills/prompt;
    ".claude/skills/procedure-expert".source = ./skills/procedure-expert;
    ".claude/skills/defer".source = ./skills/defer;
    ".claude/skills/challenge".source = ./skills/challenge;
    ".claude/skills/upgrade-risk".source = ./skills/upgrade-risk;
  };

  # Deploy as writable copy (not symlink) so `claude plugin install` can write
  # to it. Claude Code also persists its own /config choices here (theme,
  # editorMode, model, tui, permissions.defaultMode, ...), so merge rather than
  # overwrite: keys defined below win, everything else on disk survives.
  # Consequence: dropping a key here no longer removes it from the live file.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    if [ -f "$settings" ]; then
      ${unstable.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${./settings.json} \
        > "$settings.new" && mv "$settings.new" "$settings"
    else
      install -m 644 ${./settings.json} "$settings"
    fi
  '';

  # Deploy hooks as executable copies (Nix store is read-only)
  home.activation.claudeHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.claude/hooks"
    install -m 755 ${
      ./hooks/cbm-code-discovery-gate
    } "$HOME/.claude/hooks/cbm-code-discovery-gate"
    install -m 755 ${
      ./hooks/cbm-session-reminder
    } "$HOME/.claude/hooks/cbm-session-reminder"
    # Imported by the hooks in this directory, which Python resolves from the
    # running script's own directory. Not executable: nothing runs it directly.
    install -m 644 ${./hooks/shellwords.py} "$HOME/.claude/hooks/shellwords.py"
    install -m 755 ${
      ./hooks/gcloud-command-gate
    } "$HOME/.claude/hooks/gcloud-command-gate"
    install -m 755 ${
      ./hooks/git-local-path-guard
    } "$HOME/.claude/hooks/git-local-path-guard"
    install -m 755 ${
      ./hooks/protected-path-guard
    } "$HOME/.claude/hooks/protected-path-guard"
    install -m 755 ${
      ./hooks/plan-verified-guard
    } "$HOME/.claude/hooks/plan-verified-guard"
    install -m 755 ${
      ./hooks/edit-content-guard
    } "$HOME/.claude/hooks/edit-content-guard"
    install -m 755 ${
      ./hooks/format-after-edit
    } "$HOME/.claude/hooks/format-after-edit"
    install -m 755 ${
      ./hooks/session-end-inbox
    } "$HOME/.claude/hooks/session-end-inbox"
  '';

  # Status line script (referenced by settings.json statusLine.command)
  home.activation.claudeStatusLine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 755 ${
      ./statusline-command.sh
    } "$HOME/.claude/statusline-command.sh"
  '';

  # Subagent status line script (referenced by settings.json subagentStatusLine.command)
  home.activation.claudeSubagentStatusLine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 755 ${
      ./subagent-statusline.sh
    } "$HOME/.claude/subagent-statusline.sh"
  '';

  # Pin the MCP binary at the stable ~/.local/bin path that the MCP
  # registration (~/.claude.json) and the discovery hook both reference.
  home.activation.claudeCbmBinary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/bin"
    ln -sf ${codebase-memory-mcp}/bin/codebase-memory-mcp \
      "$HOME/.local/bin/codebase-memory-mcp"
  '';
}
