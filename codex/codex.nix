{ pkgs, lib, ... }:
let
  sharedHooks = [
    "gcloud-command-gate"
    "git-local-path-guard"
    "protected-path-guard"
    "edit-content-guard"
    "plan-verified-guard"
    "format-after-edit"
    "shellwords.py"
  ];
  handler = name: {
    type = "command";
    command = "env -u DEVELOPER_DIR python3 ~/.codex/hooks/${name}";
    timeout = 60;
  };
  hooks = {
    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = map handler [ "gcloud-command-gate" "git-local-path-guard" ];
        }
        {
          matcher = "apply_patch";
          hooks = [ (handler "patch-adapter.py") ];
        }
      ];
      PostToolUse = [
        {
          matcher = "apply_patch";
          hooks = [ (handler "patch-adapter.py") ];
        }
      ];
    };
  };
in {
  home.file = {
    ".codex/development.config.toml".source = ./development.config.toml;
    ".codex/AGENTS.md".source = pkgs.writeText "codex-AGENTS.md"
      (builtins.readFile ../claude/CLAUDE.md + "\n" + builtins.readFile ./AGENTS.md);
    ".codex/hooks.json".source =
      pkgs.writeText "codex-hooks.json" (builtins.toJSON hooks);
    ".codex/hooks/patch-adapter.py".source = ./hooks/patch-adapter.py;
    ".codex/skills/coding-conventions" = {
      source = ./skills/coding-conventions;
      recursive = true;
    };
    ".codex/skills/coding-conventions/references" = {
      source = ../claude/rules;
      recursive = true;
    };
    ".codex/skills/commit/SKILL.md".source = ../claude/skills/commit/SKILL.md;
  } // lib.genAttrs (map (name: ".codex/hooks/${name}") sharedHooks)
    (target: { source = ../claude/hooks + "/${builtins.baseNameOf target}"; });
}
