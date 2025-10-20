{ config, pkgs, ... }:

# TODO: See https://www.reddit.com/r/NixOS/comments/vc3srj/comment/icbwtvr/ for
#       a way to improve config with mutable dotfiles/config files

{
  home.packages = with pkgs; [
    golangci-lint # Golang linter
    golangci-lint-langserver # Language server for golangci-lint
    gopls # Official LSP for Go
    gotools # Various tools and packages for Go static analysis
    hadolint # Dockerfile linter
    markdownlint-cli # Style checker and lint tool for Markdown
    nixd # Language server for nix
    nixfmt-classic # Formatter for nix
    nodePackages.graphql-language-service-cli # GrapQL LSP
    sqruff # SQL formatter/linter
    tree-sitter
    typescript-language-server
    universal-ctags
  ];
  # Setup default tags for universal-ctags
  home.file.".ctags.d/default.ctags".source = ./.ctags.d/default.ctags;
  # User config for sqruff
  home.file.".sqruff".source = ./.sqruff;
  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
      extraLuaConfig = ''
        ${builtins.readFile ./lua/options.lua}
        ${builtins.readFile ./lua/autocmds.lua}
        ${builtins.readFile ./lua/usercmds.lua}
        ${builtins.readFile ./lua/diagnostic.lua}
        ${builtins.readFile ./lua/keymaps.lua}
        ${builtins.readFile ./lua/plugins/sql.lua}
      '';
      plugins = with pkgs.vimPlugins; [
        {
          # Make file browsing easier
          plugin = nerdtree;
          type = "lua";
          config = ''
            -- NERDTree
            ${builtins.readFile ./lua/plugins/nerdtree.lua}
          '';
        }
        {
          plugin = nvim-treesitter.withAllGrammars;
          type = "lua";
          config = ''
            -- Syntax Highlighting via nvim-treesitter
            ${builtins.readFile ./lua/plugins/treesitter.lua}
          '';
        }
        # Color scheme: https://github.com/rebelot/kanagawa.nvim
        # TIP: Use 'colorscheme kanagawa-lotus' for a bright scheme
        {
          plugin = kanagawa-nvim;
          type = "lua";
          config = ''
            vim.cmd.colorscheme('kanagawa-wave')
          '';
        }
        # Mark which lines have changed
        vim-gitgutter
        # Quick and easy file searching
        {
          plugin = fzf-lua;
          type = "lua";
          config = ''
            ${builtins.readFile ./lua/plugins/fzf.lua}
          '';
        }
        # Incremental tag generation
        {
          plugin = vim-gutentags;
          type = "lua";
          config = ''
            ${builtins.readFile ./lua/plugins/gutentags.lua}
          '';
        }
        # LSP
        {
          plugin = nvim-lspconfig;
          type = "lua";
          config = ''
            ${builtins.readFile ./lua/plugins/lspconfig.lua}
          '';
        }
        # Formatters (hooked up via LSP)
        {
          plugin = none-ls-nvim;
          type = "lua";
          config = ''
            local null_ls = require("null-ls")
            null_ls.setup({
              sources = {
                null_ls.builtins.diagnostics.hadolint,
                null_ls.builtins.formatting.gofmt,
                null_ls.builtins.formatting.goimports,
                null_ls.builtins.formatting.nixfmt,
                -- SQL
                -- Passing a shared config file to avoid per project config
                null_ls.builtins.diagnostics.sqruff.with({
                  args = { "--config", "${config.home.homeDirectory}/.sqruff", "lint", "--format", "github-annotation-native", "$FILENAME" },
                }),
                null_ls.builtins.formatting.sqruff.with({
                  args = { "--config", "${config.home.homeDirectory}/.sqruff", "fix", "-" },
                }),
                null_ls.builtins.formatting.stylua,
                null_ls.builtins.diagnostics.markdownlint,
                null_ls.builtins.formatting.markdownlint
              }
            })
          '';
        }
        # Navigate Kitty scrollback with nvim
        {
          plugin = kitty-scrollback-nvim;
          type = "lua";
          config = ''
            require('kitty-scrollback').setup()
          '';
        }
      ];
    };
  };
}
