{ pkgs, lib, unstable, ... }:
let
  # MCP binary from nixpkgs-unstable; tracks the channel on `nix flake update`.
  # Provides only the executable -- the discovery hook + skill are wired below.
  # Do NOT run `codebase-memory-mcp install`/`update`: it mutates ~/.claude
  # (hooks, settings.json, skills) which this flake owns and would revert.
  inherit (unstable) codebase-memory-mcp;
in {
  # npx, for `ccusage` (statusline session-spend reporting) -- no first-party
  # `claude usage` CLI exists yet.
  home.packages = [ pkgs.nodejs ];

  # Each directory maps to one Claude Code loading mechanism, so where a file
  # lives is the whole decision -- no list to keep in sync:
  #   rules/    always in context for a session that touches a matching file
  #             (each carries `paths:` frontmatter; without it a rule loads
  #             unconditionally, which is what CLAUDE.md is for)
  #   skills/   loaded only when invoked or when Claude judges it relevant
  #   agents/   dispatchable in their own context via the Agent tool
  #   commands/ slash commands
  #
  # `recursive = true` links each file individually instead of the directory, so
  # hand-installed entries under these paths survive activation.
  home.file = {
    ".claude/CLAUDE.md".source = ./CLAUDE.md;
    ".claude/rules" = {
      source = ./rules;
      recursive = true;
    };
    ".claude/skills" = {
      source = ./skills;
      recursive = true;
    };
    ".claude/agents" = {
      source = ./agents;
      recursive = true;
    };
    ".claude/commands" = {
      source = ./commands;
      recursive = true;
    };
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
