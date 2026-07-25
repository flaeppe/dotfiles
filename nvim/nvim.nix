{ pkgs, unstable, ... }:

# TODO: See https://www.reddit.com/r/NixOS/comments/vc3srj/comment/icbwtvr/ for
#       a way to improve config with mutable dotfiles/config files

{
  home.packages = (with pkgs; [
    ast-grep # Structural (AST-aware) code search across TS/Go/Python
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
    postgres-language-server # SQL LSP built on the real Postgres grammar
    sqruff # SQL formatter/linter
    stylua # Formatter for Lua
    # vtsls over typescript-language-server: same tsserver underneath, but it
    # exposes the tsserver-only commands (see lspconfig.lua).
    vtsls
    universal-ctags
  ]);
  # Setup default tags for universal-ctags (every *.ctags in ~/.ctags.d is
  # loaded automatically)
  home.file.".ctags.d/default.ctags".source = ./.ctags.d/default.ctags;
  home.file.".ctags.d/graphql.ctags".source = ./.ctags.d/graphql.ctags;
  # User config for sqruff
  home.file.".sqruff".source = ./.sqruff;
  # Persistent blacklist for the fzf-lua grep picker (gitignore syntax);
  # add more entries here and switch to apply.
  home.file.".config/nvim/grep-blacklist".source = ./grep-blacklist;
  # Extra treesitter queries, merged with the ones nvim-treesitter ships via a
  # leading `; extends` directive.
  home.file.".config/nvim/queries/ecma/injections.scm".source =
    ./queries/ecma/injections.scm;
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
        ${builtins.readFile ./lua/keylog.lua}
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
          # Structural motions/selections (]f, af, at) driven by the same
          # parsers as highlighting. Must load after nvim-treesitter.
          {
            plugin = nvim-treesitter-textobjects;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/textobjects.lua}
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
              -- Rendered through an fzf-lua picker, so it loads with fzf-lua
              -- rather than as its own plugin entry.
              ${builtins.readFile ./lua/plugins/dojo.lua}
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
          # Symbol outline, backed by the LSP where one is attached
          {
            plugin = aerial-nvim;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/aerial.lua}
            '';
          }
          # Formatters and linters (hooked up via LSP)
          {
            plugin = none-ls-nvim;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/none-ls.lua}
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
          # Pretty-render markdown (code highlighting, mermaid, etc.) in a
          # live browser preview
          {
            plugin = markdown-preview-nvim;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/markdown-preview.lua}
            '';
          }
        ] ++ [
          # GitHub Copilot
          {
            # copilot-language-server bundles unsigned native modules
            # (crypt32*.node) for OS keychain access. Unsigned code has no
            # stable identity for macOS to remember, so it reprompts for
            # keychain access on every launch regardless of "Always Allow" --
            # ad-hoc signing gives it one. Darwin-only: /usr/bin/codesign
            # doesn't exist on Linux, where this plugin is unaffected.
            plugin = if pkgs.stdenv.isDarwin then
              unstable.vimPlugins.copilot-vim.overrideAttrs (old: {
                postFixup = ''
                  ${old.postFixup or ""}
                  find $out -name '*.node' -exec /usr/bin/codesign --force --sign - {} \;
                '';
              })
            else
              unstable.vimPlugins.copilot-vim;
            type = "lua";
            config = ''
              ${builtins.readFile ./lua/plugins/copilot.lua}
            '';
          }
        ];
    };
  };
}
