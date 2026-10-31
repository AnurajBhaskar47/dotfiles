colorscheme jellybeans

filetype on
filetype plugin on
filetype indent on

set nocompatible
set rnu
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set clipboard=unnamedplus,unnamed,autoselect
set ignorecase
set smartcase
set showcmd
set showmode
set showmatch
set hlsearch
set history=1000
set wildmenu
set wildmode=list:longest
set wildignore=*.docx,*.jpg,*.jpeg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx
set guifont=JetBrainsMono-Regular
set scrolloff=10

syntax on

call plug#begin('~/.vim/plugged')

" List your plugins here
" Plug 'SirVer/ultisnips'
Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-commentary'
Plug 'gabrielsimoes/cfparser.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

call plug#end()

" let g:airline#extensions#tabline#enabled = 1
" let g:airline#extensions#tabline#left_sep = ''
" let g:airline#extensions#tabline#left_alt_sep = ''
" let g:airline#extensions#tabline#right_sep = ''
" let g:airline#extensions#tabline#right_alt_sep = ''

" let g:airline_left_sep = ''
" let g:airline_left_alt_sep = ''
" let g:airline_right_sep = ''
" let g:airline_right_alt_sep = ''

let mapleader=" "
nnoremap Y y$
nnoremap <Esc> <cmd>silent nohl<CR><Esc>
nnoremap <leader>pv <cmd>silent Ex<CR><Esc>

nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
