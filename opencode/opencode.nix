{ ... }: {
  xdg.configFile = {
    "opencode/opencode.json".source = ./opencode.json;
    "opencode/tui.json".source = ./tui.json;
    "opencode/AGENTS.md".source = ./AGENTS.md;

    "opencode/agent" = {
      source = ./agent;
      recursive = true;
    };

    "opencode/command" = {
      source = ./command;
      recursive = true;
    };

    "opencode/skills" = {
      source = ./skills;
      recursive = true;
    };
  };
}
