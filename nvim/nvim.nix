{ config, pkgs, ... }:

# TODO: See https://www.reddit.com/r/NixOS/comments/vc3srj/comment/icbwtvr/ for
#       a way to improve config with mutable dotfiles/config files

let
  gruvboxBaby = pkgs.fetchFromGitHub {
    owner = "luisiacc";
    repo = "gruvbox-baby";
    rev = "71cbfd16f721a0119425786085e418eb7c7d6dac";
    sha256 = "vNscOzDglpI2RGK+fci/rsn4wWh9SCxRZv8g9TJyPvc=";
  };
in

{
  # XML formatter for vim
  xdg.configFile."nvim/formatters/xml.vim".source = ./formatters/xml.vim;

  home.packages = with pkgs; [
    gopls
    nodePackages.graphql-language-service-cli
    tree-sitter
    typescript-language-server
    universal-ctags
  ];
  # Setup default tags for universal-ctags
  home.file.".ctags.d/default.ctags".source = ./.ctags.d/default.ctags;
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
        :command! -range FormatSQL <line1>,<line2>!sqlformat --reindent_aligned --keywords upper --identifiers lower -
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
              playground = {
                enable = true,
                disable = {},
                updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
                persist_queries = false -- Whether the query persists across vim sessions
              },
            }
          '';
        }
        # Nvim tree-sitter playground
        playground
        # Gruvbox color scheme, for tree-sitter
        {
          plugin = gruvboxBaby;
          type = "lua";
          config = ''
            local colors = require("gruvbox-baby.colors").config()
            vim.g.gruvbox_baby_function_style = "NONE"
            vim.g.gruvbox_baby_highlights = {
                Todo = {fg = colors.gray, bg = colors.medium_gray, style = "bold"},
                ["@operator"] = {fg = colors.red},
                ["@constant"] = {fg = colors.pink},
                ["@definition.constant"] = {fg = colors.pink},
                ["@constant.builtin"] = {fg = colors.magenta},
                ["@func.builtin"] = {fg = colors.magenta},
                ["@function.builtin"] = {fg = colors.magenta},
                ["@type.builtin"] = {fg = colors.magenta},
                -- Color for 'gitgutter'
                GitGutterAdd = {fg = colors.soft_green},
            }

            -- 'gitcommit' language highlights
            vim.api.nvim_set_hl(0, "@text.gitcommit", { fg = colors.comment })  -- text
            vim.api.nvim_set_hl(0, "@text.title.gitcommit", { fg = colors.foreground })  -- title
            vim.api.nvim_set_hl(0, "@spell.gitcommit", { fg = colors.soft_yellow })  -- message,
            vim.api.nvim_set_hl(0, "@text.reference.gitcommit", { fg = colors.pink, bold = true })  -- branch
            vim.api.nvim_set_hl(0, "@text.uri.gitcommit", { fg = colors.light_blue })  -- filepath
            vim.api.nvim_set_hl(0, "@keyword.gitcommit", { fg = colors.orange })  -- change
            -- 'diff' language highlights (injected by 'gitcommit')
            vim.api.nvim_set_hl(0, "@constant.diff", { fg = colors.pink })  -- commit
            vim.api.nvim_set_hl(0, "@attribute.diff", { fg = colors.forest_green })  -- location
            vim.api.nvim_set_hl(0, "@function.diff", { fg = colors.foreground, bold = true })  -- command
            vim.api.nvim_set_hl(0, "@text.diff.add", { fg = colors.soft_green })  -- addition, new_file
            vim.api.nvim_set_hl(0, "@text.diff.delete", { fg = colors.error_red })  -- deletion, old_file

            vim.cmd[[colorscheme gruvbox-baby]]
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
            " FZF floating window support
            let g:fzf_layout = { 'window': 'call FloatingFZF()' }
            function! FloatingFZF()
              let buf = nvim_create_buf(v:false, v:true)
              call setbufvar(buf, '&signcolumn', 'no')

              let width = float2nr(&columns - (&columns * 2 / 10))
              let height = &lines - 3
              let y = &lines - 3
              let x = float2nr((&columns - width) / 2)

              let opts = {
                    \ 'relative': 'editor',
                    \ 'row': y,
                    \ 'col': x,
                    \ 'width': width,
                    \ 'height': height
                    \ }

              call nvim_open_win(buf, v:true, opts)
            endfunction
            au FileType fzf set nonu nornu
            " Text and background color of floating window
            highlight NormalFloat cterm=NONE ctermfg=14 ctermbg=0 gui=NONE guifg=#bfbfbf guibg=#1a1a1a
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
          '';
        }
      ];
    };
  };
}
