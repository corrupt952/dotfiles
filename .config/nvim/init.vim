filetype off
filetype plugin indent off

set ttimeout
set ttimeoutlen=20

let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

if !isdirectory(s:dein_repo_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath^=' . s:dein_repo_dir

if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  let s:toml = '~/.config/nvim/dein.toml'
  let s:lazy_toml = '~/.config/nvim/dein_lazy.toml'
  call dein#load_toml(s:toml, {'lazy': 0})
  call dein#load_toml(s:lazy_toml, {'lazy': 1})

  call dein#end()
  call dein#save_state()
endif

if dein#check_install()
  call dein#install()
endif

" Required:
filetype plugin indent on

set scrolloff=5
set textwidth=0
set nobackup
set autoread
set noswapfile
set hidden
set backspace=indent,eol,start
set formatoptions=lmoq
set vb t_vb=
set browsedir=buffer
set whichwrap=b,s,<,>,[,],~
set showcmd
set ruler
set cmdheight=2
set showmode
set nomodeline
set mouse=a
set incsearch

" Editor {{{
set number
set showmatch
set laststatus=2
" }}}

" Indent {{{
set autoindent
set smartindent
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set smarttab
set clipboard=unnamed
" }}}

" scheme {{{
colorscheme hybrid
set background=dark
syntax on
hi LineNr ctermfg=7
hi CursorLineNr ctermfg=3
set cursorline
hi clear CursorLine
hi Normal guibg=NONE ctermbg=NONE
" }}}

if (exists('+colorcolumn'))
    set colorcolumn=80
    hi ColorColumn ctermbg=167
endif

" Functions {{{
" type ... p(revious) or n(ext)
" mode ... n(ormal) or v(isual) or i(nsert)
function! JumpToSameIndentLine(type, mode)
    " TODO: visual mode support
    if a:mode == "v"
        execute "normal! gv\<Esc>"
    endif

    if a:type == "p"
        let search_flags = "be"
    elseif a:type == "n"
        let search_flags = "ew"
    endif

    let pos = searchpos("^". matchstr(getline("."), '\(\s*\)') ."\\S", search_flags)
    " call setpos('.', pos[1])
endfunction
" }}}

" Keymaps {{{
noremap s      <Nop>
nnoremap ZQ    <Nop>
nnoremap Q     <Nop>

nnoremap <silent> tn    :tabnew<CR>
nnoremap <silent> tt    gt

" binary
nnoremap <silent> btt   :%!xxd<CR>
nnoremap <silent> tbb   :%!xxd -r<CR>

" indent jump
nnoremap <silent> <C-k> :call JumpToSameIndentLine('p', 'n')<CR>
nnoremap <silent> <C-j> :call JumpToSameIndentLine('n', 'n')<CR>
vnoremap <silent> <C-k> :call JumpToSameIndentLine('p', 'v')<CR>
vnoremap <silent> <C-j> :call JumpToSameIndentLine('n', 'v')<CR>
" }}}

" .vimrc.local
if filereadable(expand('~/.vimrc.local'))
    source ~/.vimrc.local
endif
