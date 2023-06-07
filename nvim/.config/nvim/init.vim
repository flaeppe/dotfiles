" Detect what OS we're running on
if !exists("g:os")
    let g:os = substitute(system('uname'), '\n', '', '')
endif

if g:os == "Darwin"
    " Enable true colors support
    set termguicolors
endif

" Map the leader key to SPACE
let mapleader="\<SPACE>"


"""""""""
" Plugins
"""""""""
call plug#begin('~/.vim/plugged')

" Make file browsing easier
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
let NERDTreeIgnore = ['\.pyc$', '__pycache__', '\.js.map$',
                    \ '\.DS_STORE', 'venv', '\.mypy_cache',
                    \ '\.pytest_cache', '\.nox', '\.egg-info$',
                    \ '\.tags']

" Leader + nn for toggling the file browser
nnoremap <Leader>nn :NERDTreeToggle<CR>
" Show hidden files and folders per default in file browser
let NERDTreeShowHidden=1

" Extended syntax support
" Updating parsers on update is recommended by maintainers
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-treesitter/playground'
" Gruvbox color scheme, for tree-sitter
Plug 'luisiacc/gruvbox-baby', {'branch': 'main'}

" Mark which lines have changed
Plug 'airblade/vim-gitgutter'
" difftool for git (https://github.com/sindrets/diffview.nvim)
Plug 'nvim-lua/plenary.nvim'
Plug 'sindrets/diffview.nvim'

" Quick and easy file searching
if g:os == "Darwin"
    Plug '/usr/local/opt/fzf'
else
    Plug 'junegunn/fzf', { 'dir': '~/.fzf',  'do': './install --all' }
endif
Plug 'junegunn/fzf.vim'
" <C-p> to search files
nnoremap <silent> <C-p> :Files<CR>

" Incremental tag generation
Plug 'ludovicchabant/vim-gutentags'
let g:gutentags_ctags_tagfile = '.tags'
nnoremap <Leader>gr :GutentagsUpdate!<CR>

" Buffer and ctag search
nmap <C-e> :Tags<CR>
nmap <Leader>f :Rg<Space>

" Custom Timelog plugin
Plug '~/repos/timelog-vim'
nnoremap <Leader>tn :TimelogNewTask<CR>
nnoremap <Leader>te :TimelogEndTask<CR>
nnoremap <Leader>td :TimelogCalculateSessionDuration<CR>
nnoremap <Leader>ts :TimelogSummarise<CR>
nnoremap <Leader>tjp :TimelogJumpToProject<CR>
nnoremap <Leader>tjt :TimelogJumpToTask<CR>
nnoremap <Leader>tje :TimelogJumpToEndTime<CR>

call plug#end()


""""""""""
" Settings
""""""""""
set tabstop=4  " Render TABs using this many spaces
set shiftwidth=4 " Indentation amount for < and > commands
set number
set noerrorbells

" Syntax Highlighting via nvim-treesitter. See:
" https://github.com/nvim-treesitter/nvim-treesitter
lua <<EOF
require'nvim-treesitter.configs'.setup {
  ensure_installed = "all",
  highlight = {
    enable = true,
  },
  playground = {
    enable = true,
    disable = {},
    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
    persist_queries = false -- Whether the query persists across vim sessions
  },
}
EOF

" configure nvcode-color-schemes
let g:nvcode_termcolors=256

" Enable syntax highlightning
syntax on

" Set colorscheme
" See: https://github.com/luisiacc/gruvbox-baby
lua <<EOF
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
EOF


" checks if terminal has 24-bit color support
if (has("termguicolors"))
    set termguicolors
    hi LineNr ctermbg=NONE guibg=NONE
endif

" Use the system clipboard
if g:os == "Darwin"
    let g:clipboard = {'copy': {'+': 'pbcopy', '*': 'pbcopy'}, 'paste': {'+': 'pbpaste', '*': 'pbpaste'}, 'name': 'pbcopy', 'cache_enabled': 0}
endif
set clipboard+=unnamedplus

" Whitespace
fun! TrimWhitespace()
    let l:save_cursor = getpos('.')
    %s/\s\+$//e
    call setpos('.', l:save_cursor)
endfun

" Tab config for different syntaxes
set tabstop=2 softtabstop=2 expandtab shiftwidth=2 smarttab
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType vim setlocal ts=8 sts=0 sw=4 expandtab smarttab
autocmd FileType html setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType make setlocal noexpandtab

" Relative line number on by default
set relativenumber

augroup vimrc
    " Clean the autogroup
    autocmd!

    " Trim whitespace
    autocmd BufWritePost * :call TrimWhitespace()

augroup END

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

" Formatters
" Via: pip install sqlparse
:command! -range FormatSQL <line1>,<line2>!sqlformat --reindent_aligned --keywords upper --identifiers lower -
:command! -range FormatJSON <line1>,<line2>!jq .
source ~/.config/nvim/formatters/xml.vim

" Disable unused providers
let g:loaded_python_provider = 0
let g:loaded_perl_provider = 0
let g:loaded_ruby_provider = 0
let g:loaded_node_provider = 0
" Setup Python 3 interpreter
let g:python3_host_prog = $HOME.'/.vim/.venv/bin/python3'

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

" config for 'sindrets/diffview.nvim'
lua <<EOF
local actions = require("diffview.actions")

require("diffview").setup({
  use_icons = false,  -- Requires nvim-wev-devicons
})
EOF
