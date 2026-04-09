{ lib, ... }:
let
  opencode = ../opencode;

  # Rules shared with OpenCode -- auto-loaded by paths in Claude Code
  # (single source in opencode/skills/, deployed as ~/.claude/rules/)
  sharedRules = [
    "golang" "golang-test" "jest" "nix"
    "pytest" "python" "test" "typescript" "vitest"
  ];

  # Always-loaded rules (no paths = loaded in every session, like CLAUDE.md)
  alwaysRules = [
    "commit"
  ];

  # Skills shared with OpenCode -- user-invocable in Claude Code
  # (single source in opencode/skills/, deployed as ~/.claude/skills/)
  sharedSkills = [
    "general" "planning"
  ];

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
    value = { source = "${opencode}/skills/${name}"; recursive = true; };
  }) sharedSkills);
in {
  home.file = sharedRuleEntries // alwaysRuleEntries // sharedSkillEntries // {
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
  };

  # Deploy as writable copy (not symlink) so `claude plugin install` can write to it
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 644 ${./settings.json} "$HOME/.claude/settings.json"
  '';
}
