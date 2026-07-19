{ lib, unstable, multiRepoRoot ? "~/anyfin", ... }:
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
  sharedSkills = [ "commit" "general" "planning" "docs-expert" "deps-expert" "correlation-expert" ];

  # Claude subagents -- thin wrappers that load the matching skill, dispatchable
  # in their own context via the Agent tool (single source stays in the skill).
  claudeAgents = [ "docs-expert" "correlation-expert" "deps-expert" ];

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

  # Skills whose content names a "multi-repo work" root -- ~/anyfin at the
  # work/macOS config. Rendered per-file with that path substituted rather
  # than symlinked verbatim, so each home-manager config can point it at its
  # own filesystem layout (e.g. ~/repos here). Assumes a flat skill directory
  # (no subdirectories); add handling for those if a skill here grows one.
  multiRepoRootSkills = [ "planning" "docs-expert" ];

  renderSkillFile = name: file:
    lib.replaceStrings [ "~/anyfin" ] [ multiRepoRoot ]
      (builtins.readFile "${opencode}/skills/${name}/${file}");

  renderedSkillEntries = builtins.listToAttrs (builtins.concatMap (name:
    map (file: {
      name = ".claude/skills/${name}/${file}";
      value.text = renderSkillFile name file;
    }) (builtins.attrNames (builtins.readDir "${opencode}/skills/${name}"))
  ) multiRepoRootSkills);

  sharedSkillEntries = builtins.listToAttrs (map (name: {
    name = ".claude/skills/${name}";
    value = {
      source = "${opencode}/skills/${name}";
      recursive = true;
    };
  }) (builtins.filter (name: !builtins.elem name multiRepoRootSkills) sharedSkills));
in {
  home.file = sharedRuleEntries // alwaysRuleEntries // sharedSkillEntries
    // renderedSkillEntries // claudeAgentEntries // {
    # Global instructions -- shared, single source in opencode/AGENTS.md
    ".claude/CLAUDE.md".source = "${opencode}/AGENTS.md";

    # Claude-specific workflow commands
    ".claude/skills/explore".source = ./skills/explore;
    ".claude/skills/pr".source = ./skills/pr;
    ".claude/skills/pr-playbook".source = ./skills/pr-playbook;
    ".claude/skills/fix-pr".source = ./skills/fix-pr;
    ".claude/skills/research".source = ./skills/research;
    ".claude/skills/pr-review".source = ./skills/pr-review;
    ".claude/skills/run-tests".source = ./skills/run-tests;
    ".claude/skills/codebase-memory".source = ./skills/codebase-memory;
    ".claude/skills/test-expert".source = ./skills/test-expert;
    ".claude/skills/commit-msg".source = ./skills/commit-msg;
    ".claude/skills/analyze".source = ./skills/analyze;
    ".claude/skills/prompt".source = ./skills/prompt;
    ".claude/skills/defer".source = ./skills/defer;
    ".claude/skills/upgrade-risk".source = ./skills/upgrade-risk;
  };

  # Deploy as writable copy (not symlink) so `claude plugin install` can write to it
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 644 ${./settings.json} "$HOME/.claude/settings.json"
  '';

  # Deploy codebase-memory-mcp hooks as executable copies (Nix store is read-only)
  home.activation.claudeHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.claude/hooks"
    install -m 755 ${
      ./hooks/cbm-code-discovery-gate
    } "$HOME/.claude/hooks/cbm-code-discovery-gate"
    install -m 755 ${
      ./hooks/cbm-session-reminder
    } "$HOME/.claude/hooks/cbm-session-reminder"
  '';

  # Status line script (referenced by settings.json statusLine.command)
  home.activation.claudeStatusLine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 755 ${
      ./statusline-command.sh
    } "$HOME/.claude/statusline-command.sh"
  '';

  # Pin the MCP binary at the stable ~/.local/bin path that the MCP
  # registration (~/.claude.json) and the discovery hook both reference.
  home.activation.claudeCbmBinary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/bin"
    ln -sf ${codebase-memory-mcp}/bin/codebase-memory-mcp \
      "$HOME/.local/bin/codebase-memory-mcp"
  '';
}
