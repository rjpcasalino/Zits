{ pkgs, ... }:
{
  programs.vim = {
    enable = true;
    defaultEditor = true;
    package = (pkgs.vim-full.override { }).customize {
      name = "vim";
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [
          ale
          colorizer
          copilot-vim
          csv-vim
          lightline-vim
          matchit-zip
          vim-go
          vim-nix
          vim-terraform
          vim-lsp
          vim-lastplace
          vim-signify
        ];
        opt = [ ];
      };
      vimrcConfig.customRC = ''

          set nocompatible            " Leave vi-compatibility in the 1970s
          filetype plugin indent on   " Auto-detect file types and load their indent rules

          " Keep the filesystem completely clean. Git handles version control now.
          set noswapfile
          set nobackup
          set nowritebackup

          " Modern text navigation
          set scrolloff=8             " Keep 8 lines of context above/below the cursor
          set signcolumn=yes          " Always show the left gutter (stops text from jumping when errors appear)
          set updatetime=100          " Faster refresh for plugins/git-gutter if added later
          set hidden                  " Allow changing buffers without saving them first

          " Search behavior
          set ignorecase              " Case-insensitive search...
          set smartcase               " ...unless you type a capital letter
          set incsearch               " Show search matches as you type
          set hlsearch                " Highlight search results
          " Enable 24-bit RGB color in the terminal
          set termguicolors

          " Line numbers: Relative for fast jumping (e.g., '5j'), absolute for current line
          set number
          set relativenumber

          if !has('gui_running')
              set t_Co=256
          endif

          colorscheme habamax
          syntax on
          set expandtab
          set tabstop=4
          set ruler
          set spelllang=en_us
          set list
          set listchars=eol:¬,tab:▸\ ,trail:·
          set wildmenu
          set wildmode=longest,list,full

          let g:netrw_preview = 1
          let g:netrw_banner = 1
          let g:netrw_liststyle = 3
          let g:netrw_winsize = 25

          let g:ale_sign_error = '✘'
          let g:ale_sign_warning = '⚠'
          highlight ALEErrorSign ctermbg=NONE ctermfg=red
          highlight ALEWarningSign ctermbg=NONE ctermfg=yellow

          noremap <F11> :tabprevious<CR>
          noremap <F12> :tabnext<CR>

          augroup vimrc
              autocmd!
              au BufRead,BufNewFile *.tex,*.md,*.txt,*.man,*.ms setlocal spell
              hi clear SpellBad
              hi SpellBad cterm=underline,bold ctermfg=red
          augroup END

          augroup PaperMode
              autocmd!
              autocmd BufEnter *.txt,*.tex set background=light
              autocmd BufEnter *.txt,*.tex highlight Normal     ctermbg=231 ctermfg=235 guibg=#FFFFFF guifg=#1c1c1c
              autocmd BufEnter *.txt,*.tex highlight NonText    ctermbg=231 ctermfg=235 guibg=#FFFFFF guifg=#1c1c1c
              autocmd BufEnter *.txt,*.tex set syntax=off
              autocmd BufEnter *.txt,*.tex set spell!

              autocmd BufEnter *.txt,*.tex let &t_EI = "\<Esc>]12;black\x7"
              autocmd BufEnter *.txt,*.tex let &t_SI = "\<Esc>]12;black\x7"
              autocmd BufEnter *.txt,*.tex let &t_SR = "\<Esc>]12;black\x7"
              autocmd BufEnter *.txt,*.tex silent! execute "normal! \<Esc>"

              autocmd BufLeave *.txt,*.tex set background=dark
              autocmd BufLeave *.txt,*.tex highlight Normal ctermbg=NONE ctermfg=NONE guibg=NONE guifg=NONE
              autocmd BufLeave *.txt,*.tex highlight NonText ctermbg=NONE ctermfg=NONE guibg=NONE guifg=NONE

              autocmd BufLeave *.txt,*.tex silent! execute "normal! \<Esc>"
          augroup END

          autocmd VimLeave * silent !echo -ne "\033]112\007"

          set laststatus=0

          runtime macros/matchit.vim
      '';
    };
  };
}
