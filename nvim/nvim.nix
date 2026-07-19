{ config, pkgs, unstable, ... }:

# TODO: See https://www.reddit.com/r/NixOS/comments/vc3srj/comment/icbwtvr/ for
#       a way to improve config with mutable dotfiles/config files

{
  home.packages = (with pkgs; [
    golangci-lint # Golang linter
    golangci-lint-langserver # Language server for golangci-lint
    gopls # Official LSP for Go
    gotools # Various tools and packages for Go static analysis
    hadolint # Dockerfile linter
    markdownlint-cli # Style checker and lint tool for Markdown
    marksman # Language server for Markdown
    nixd # Language server for nix
    nixfmt # Formatter for nix
    graphql-language-service-cli # GrapQL LSP
    sqruff # SQL formatter/linter
    stylua # Formatter for Lua
    typescript-language-server
    universal-ctags
  ]);
  # Setup default tags for universal-ctags
  home.file.".ctags.d/default.ctags".source = ./.ctags.d/default.ctags;
  # User config for sqruff
  home.file.".sqruff".source = ./.sqruff;
  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
      withRuby = true;
      withPython3 = true;
      initLua = ''
        ${builtins.readFile ./lua/options.lua}
        ${builtins.readFile ./lua/autocmds.lua}
        ${builtins.readFile ./lua/usercmds.lua}
        ${builtins.readFile ./lua/diagnostic.lua}
        ${builtins.readFile ./lua/keymaps.lua}
        ${builtins.readFile ./lua/plugins/sql.lua}
      '';
      plugins = with pkgs.vimPlugins;
        [
          {
            # File icons for fzf-lua's picker UI. fzf-lua only lazily
            # requires this on first icon render, so without an eager
            # require here checkhealth won't see it in package.loaded even
            # though it's fully functional.
            plugin = nvim-web-devicons;
            type = "lua";
            config = ''
              require('nvim-web-devicons').setup()
            '';
          }
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
            plugin = nvim-treesitter.withPlugins (p:
              with p; [
                # Core languages
                go
                typescript
                tsx
                javascript
                python
                # Config/infra
                nix
                json
                yaml
                toml
                dockerfile
                bash
                ini
                properties
                # Docs/misc
                markdown
                markdown_inline
                sql
                graphql
                lua
                gitcommit
                gitignore
                gitattributes
                fish
                proto
                html
                css
                vim
                vimdoc
                comment
                regex
                jsdoc
                diff
                make
                kitty
                editorconfig
              ]);
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
        ] ++ [
          # GitHub Copilot
          {
            plugin = unstable.vimPlugins.copilot-vim;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/copilot.lua}
            '';
          }
        ];
    };
  };
}
