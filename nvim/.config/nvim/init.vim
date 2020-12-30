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
                    \ '\.pytest_cache', '\.nox', '\.egg-info$']

" Leader + nn for toggling the file browser
nnoremap <Leader>nn :NERDTreeToggle<CR>
" Show hidden files and folders per default in file browser
let NERDTreeShowHidden=1

" Extended syntax support
" Updating parsers on update is recommended by maintainers
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
" A couple of color schemes
" (Extended from: Plug 'christianchiarulli/nvcode-color-schemes.vim')
Plug '~/repos/nvcode-color-schemes.vim'

" Dockerfile syntax support
Plug 'ekalinin/Dockerfile.vim'

" Mark which lines have changed
Plug 'airblade/vim-gitgutter'

" Quick and easy file searching
if g:os == "Darwin"
    Plug '/usr/local/opt/fzf'
else
    Plug 'junegunn/fzf', { 'dir': '~/.fzf',  'do': './install --all' }
endif
Plug 'junegunn/fzf.vim'
" <C-p> to search files
nnoremap <silent> <C-p> :Files<CR>
" Buffer and ctag search
nmap <C-e> :Tags<CR>
nmap <Leader>f :Rg<Space>

" Incremental tag generation
Plug 'ludovicchabant/vim-gutentags'
let g:gutentags_ctags_tagfile = '.tags'
nnoremap <Leader>gr :GutentagsUpdate!<CR>

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
  ensure_installed = "maintained",
  highlight = {
    enable = true,
  },
}
EOF

" configure nvcode-color-schemes
let g:nvcode_termcolors=256

syntax on
colorscheme gruvbox2

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
