{ pkgs, lib, ... }:
let
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
    ".codex/AGENTS.md".source = pkgs.writeText "codex-AGENTS.md"
      (builtins.readFile ../claude/CLAUDE.md + "\n" + builtins.readFile ./AGENTS.md);
    ".codex/hooks.json".source =
      pkgs.writeText "codex-hooks.json" (builtins.toJSON hooks);
    ".codex/skills/coding-conventions" = {
      source = ./skills/coding-conventions;
      recursive = true;
    };
    ".codex/skills/coding-conventions/references" = {
      source = ../claude/rules;
      recursive = true;
    };
    ".codex/skills/commit/SKILL.md".source = ../claude/skills/commit/SKILL.md;
  };

  # Deploy hooks as copies so Python resolves sibling imports from this directory.
  home.activation.codexHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.codex/hooks"
    install -m 755 ${
      ../claude/hooks/gcloud-command-gate
    } "$HOME/.codex/hooks/gcloud-command-gate"
    install -m 755 ${
      ../claude/hooks/git-local-path-guard
    } "$HOME/.codex/hooks/git-local-path-guard"
    install -m 755 ${
      ../claude/hooks/protected-path-guard
    } "$HOME/.codex/hooks/protected-path-guard"
    install -m 755 ${
      ../claude/hooks/edit-content-guard
    } "$HOME/.codex/hooks/edit-content-guard"
    install -m 755 ${
      ../claude/hooks/plan-verified-guard
    } "$HOME/.codex/hooks/plan-verified-guard"
    install -m 755 ${
      ../claude/hooks/format-after-edit
    } "$HOME/.codex/hooks/format-after-edit"
    # Imported by the hooks in this directory, which Python resolves from the
    # running script's own directory. Not executable: nothing runs it directly.
    install -m 644 ${
      ../claude/hooks/shellwords.py
    } "$HOME/.codex/hooks/shellwords.py"
    install -m 755 ${
      ./hooks/patch-adapter.py
    } "$HOME/.codex/hooks/patch-adapter.py"

    # Sentry CLI deploys its dynamic skill set into existing agent roots. Keep
    # this root writable; upgrades create and remove the skill directories.
    mkdir -p "$HOME/.agents/skills"
  '';
}
