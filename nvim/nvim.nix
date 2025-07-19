{ config, pkgs, ... }:

# TODO: See https://www.reddit.com/r/NixOS/comments/vc3srj/comment/icbwtvr/ for
#       a way to improve config with mutable dotfiles/config files

{
  # XML formatter for vim
  xdg.configFile."nvim/formatters/xml.vim".source = ./formatters/xml.vim;

  home.packages = with pkgs; [
    golangci-lint # Golang linter
    golangci-lint-langserver # Language server for golangci-lint
    gopls # Official LSP for Go
    gotools # Various tools and packages for Go static analysis
    hadolint # Dockerfile linter
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
      extraPython3Packages = pyPkgs: with pyPkgs; [ sqlparse ];
      extraConfig = ''
        " Settings
        set tabstop=4  " Render TABs using this many spaces
        set shiftwidth=4 " Indentation amount for < and > commands
        set number
        set noerrorbells
        " Enable syntax highlightning
        syntax on
        " Use the system clipboard
        let g:clipboard = {'copy': {'+': 'pbcopy', '*': 'pbcopy'}, 'paste': {'+': 'pbpaste', '*': 'pbpaste'}, 'name': 'pbcopy', 'cache_enabled': 0}
        set clipboard+=unnamedplus
        " Tab config for different syntaxes
        set tabstop=2 softtabstop=2 expandtab shiftwidth=2 smarttab
        autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
        autocmd FileType vim setlocal ts=8 sts=0 sw=4 expandtab smarttab
        autocmd FileType html setlocal ts=2 sts=2 sw=2 expandtab
        autocmd FileType make setlocal noexpandtab
        " Relative line number on by default
        set relativenumber
        " Whitespace
        fun! TrimWhitespace()
            let l:save_cursor = getpos('.')
            %s/\s\+$//e
            call setpos('.', l:save_cursor)
        endfun
        augroup vimrc
            " Clean the autogroup
            autocmd!
            " Trim whitespace
            autocmd BufWritePost * :call TrimWhitespace()
        augroup END
        " Formatters
        :command! -range FormatJSON <line1>,<line2>!jq .
        source ~/.config/nvim/formatters/xml.vim
        " Disable unused providers
        let g:loaded_perl_provider = 0
        " Status line
        set laststatus=2  " always display statusbar
        set statusline=
        set statusline+=%-10.3n\  " buffer number
        set statusline+=%f\  " filename
        set statusline+=%h%m%r%w  " status flags
        set statusline+=\[%{strlen(&ft)?&ft:'none'}]  " file type
        set statusline+=%=  " right align remainder
        set statusline+=0x%-8B  " character value
        set statusline+=%-14(%l,%c%V%)  " line, character
        set statusline+=%<%P  " file position
        " Disable mouse (:help default-mouse)
        set mouse=
        " Enable true colors support
         set termguicolors
         hi LineNr ctermbg=NONE guibg=NONE
      '';
      extraLuaConfig = ''

        vim.filetype.add({
          extension = {
            typ = 'markdown',
          },
        })

        --- Quicklist mappings
        vim.keymap.set('n', '<Leader>q', '<Cmd>copen<CR>')
        vim.keymap.set('n', '<Leader>Q', '<Cmd>cclose<CR>')
        vim.keymap.set('n', '<Leader>qj', '<Cmd>try | cnext | catch | cfirst | catch | endtry<CR>')
        vim.keymap.set('n', '<Leader>qk', '<Cmd>try | cprevious | catch | clast | catch | endtry<CR>')
        --- Display available code actions
        vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action, silent)
        --- Format buffer
        vim.keymap.set('n', '<Leader>ll', function() vim.lsp.buf.format { async = true } end, bufopts)
        --- LSP
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
        vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, bufopts)
        -- Open diagnostic in a floating window
        vim.keymap.set('n', '<Leader>le', function() vim.diagnostic.open_float(nil, { focus = false }) end, bufopts)
        -- Show/hide diagnostic
        vim.keymap.set('n', '<Leader>ts', vim.diagnostic.show, bufopts)
        vim.keymap.set('n', '<Leader>th', vim.diagnostic.hide, bufopts)
        -- Move to prev/next item
        vim.keymap.set('n', 'åd', vim.diagnostic.goto_prev, bufopts)
        vim.keymap.set('n', '¨d', vim.diagnostic.goto_next, bufopts)
        -- Diagnostic settings
        vim.diagnostic.config({
          update_in_insert = true,
          float = {
            focusable = false,
            style = "minimal",
            border = "rounded",
            source = "always",
            header = "",
            prefix = "",
          },
        })
      '';
      plugins = with pkgs.vimPlugins; [
        {
          # Make file browsing easier
          plugin = nerdtree;
          type = "lua";
          config = ''
            -- NERDTree
            vim.g.NERDTreeIgnore = {'\\.pyc$', '__pycache__', '\\.js.map$',
                                    '\\.DS_STORE', 'venv', '\\.mypy_cache',
                                    '\\.pytest_cache', '\\.nox', '\\.egg-info$',
                                    '\\.tags'}
            -- Show hidden files and folders per default in file browser
            vim.g.NERDTreeShowHidden = 1
            -- Keymaps
            vim.keymap.set('n', '<Leader>nn', ':NERDTreeToggle<CR>')
            vim.keymap.set('n', '<Leader>nf', ':NERDTreeFind<CR>')
          '';
        }
        {
          plugin = nvim-treesitter.withAllGrammars;
          type = "lua";
          config = ''
            -- Syntax Highlighting via nvim-treesitter. See:
            -- https://github.com/nvim-treesitter/nvim-treesitter
            local treesitter = require('nvim-treesitter.configs')
            treesitter.setup {
              highlight = {
                enable = true,
              },
              indent = {
                enable = true,
              },
            }
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
        fzfWrapper
        {
          plugin = fzf-vim;
          type = "viml";
          config = ''
            " Map the leader key to SPACE
            let mapleader="\<SPACE>"
            " <C-p> to search for files
            nnoremap <silent> <C-p> :Files<CR>
            " Search text with ripgrep, hidden included, except .git
            " Almost identical to builtin Rg command
            command! -bang -nargs=* CustomRg
              \ call fzf#vim#grep("rg --hidden --glob '!.git/*' --column --line-number --no-heading --color=always --smart-case -- ".fzf#shellescape(<q-args>), fzf#vim#with_preview(), <bang>0)
            nmap <Leader>f :CustomRg<Space>
            " Search ctags in the project
            nmap <C-e> :Tags<CR>
            " FZF popup window center of the screen
            let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.9 } }
            " Customize fzf colors to match color scheme
            " - fzf#wrap translates this to a set of `--color` options
            let g:fzf_colors =
            \ { 'fg':      ['fg', 'Normal'],
              \ 'bg':      ['bg', 'Normal'],
              \ 'query':   ['fg', 'Normal'],
              \ 'hl':      ['fg', 'Comment'],
              \ 'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
              \ 'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
              \ 'hl+':     ['fg', 'Statement'],
              \ 'info':    ['fg', 'PreProc'],
              \ 'border':  ['fg', 'Ignore'],
              \ 'prompt':  ['fg', 'Conditional'],
              \ 'pointer': ['fg', 'Exception'],
              \ 'marker':  ['fg', 'Keyword'],
              \ 'spinner': ['fg', 'Label'],
              \ 'header':  ['fg', 'Comment'] }

            au FileType fzf set nonu nornu
          '';
        }
        # Incremental tag generation
        {
          plugin = vim-gutentags;
          type = "viml";
          config = ''
            let g:gutentags_ctags_tagfile = '.tags'
            nnoremap <Leader>gr :GutentagsUpdate!<CR>
          '';
        }
        # LSP
        {
          plugin = nvim-lspconfig;
          type = "lua";
          config = ''
            local lspconfig = require('lspconfig')
            lspconfig.pyright.setup{
              settings = {
                pyright = {
                  -- Prefer Ruff's import organizer
                  disableOrganizeImports = true,
                },
              },
            }
            lspconfig.ruff.setup{
              commands = {
                RuffAutofix = {
                  function()
                    vim.lsp.buf.code_action {
                      context = {
                        only = { 'source.fixAll.ruff' }
                      },
                      apply = true,
                    }
                  end,
                  description = 'Ruff: Fix all auto-fixable problems',
                },
                RuffOrganizeImports = {
                  function()
                    vim.lsp.buf.code_action {
                      context = {
                        only = { 'source.organizeImports.ruff' }
                      },
                      apply = true,
                    }
                  end,
                  description = 'Ruff: Format imports',
                },
              },
            }
            lspconfig.ts_ls.setup{}
            lspconfig.graphql.setup{}
            lspconfig.gopls.setup{}
            lspconfig.golangci_lint_ls.setup{}
            lspconfig.nixd.setup{}
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
              }
            })
          '';
        }
      ];
    };
  };
}
