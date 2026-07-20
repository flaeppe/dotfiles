{ config, ... }:

{
  # i3 remains an Arch/X11-specific configuration. Keeping it out of shared
  # modules avoids pretending that its session semantics apply to macOS.
  xdg.configFile = {
    "i3/config".source = ./config;
    "i3/cheatsheet.txt".source = ./cheatsheet.txt;
    "i3status-rust/config.toml".source = ./i3status-rust.toml;
  };

  # The packaged Neovim desktop entry is marked Terminal=true. Rofi does not
  # choose a terminal emulator for that entry, so provide an explicit Kitty
  # launcher for its drun mode.
  xdg.desktopEntries.nvim = {
    name = "Neovim";
    genericName = "Text Editor";
    comment = "Edit text files in Neovim";
    exec = "kitty ${config.home.profileDirectory}/bin/nvim %F";
    terminal = false;
    icon = "nvim";
    categories = [ "Utility" "TextEditor" "Development" ];
  };
}
