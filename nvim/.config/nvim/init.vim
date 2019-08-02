" Enable true colors support
set termguicolors

" Map the leader key to SPACE
let mapleader="\<SPACE>"

" Plugins
call plug#begin('~/.vim/plugged')

" Make file browsing easier
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
let NERDTreeIgnore = ['\.pyc$', '__pycache__', '\.js.map$',
                    \ '\.DS_STORE', 'venv']

" Leader + nn for toggling the file browser
nnoremap <Leader>nn :NERDTreeToggle<CR>

" Show hidden files and folders per default in file browser
let NERDTreeShowHidden=1

" Mark which lines have changed
Plug 'airblade/vim-gitgutter'
call plug#end()

" Settings
set tabstop=4  " Render TABs using this many spaces
set shiftwidth=4 " Indentation amount for < and > commands
set number
set noerrorbells
colorscheme gruvbox

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
