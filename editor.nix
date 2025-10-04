{ pkgs, ... }:
{
  programs.vim = {
    enable = true;
    defaultEditor = true;
    package = (pkgs.vim-full.override { }).customize {
      name = "vim";
      # Install plugins for example for syntax highlighting of nix files
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [
          ale
          colorizer
          copilot-vim
          csv-vim
          csv
          lightline-vim
          matchit-zip
          vim-go
          vim-nix
          vim-terraform
          vim-lsp
        ];
        opt = [ ];
      };
      vimrcConfig.customRC = ''
        " my custom vimrc
        if !has('gui_running')
            set t_Co=256
        endif
        let g:copilot_enabled = v:false
        colorscheme default
        syntax on
        set expandtab
        set tabstop=4
        set ruler
        set hlsearch
        set spelllang=en_us
        set list
        set listchars=eol:¬,tab:▸\ ,trail:·
        set wildmenu
        set wildmode=longest,list,full
        " don't pollute dirs with swap files
        " keep them in one place
        silent !mkdir -p ~/.vim/{backup,swp}/
        set backupdir=~/.vim/backup/
        set directory=~/.vim/swp/
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
      runtime macros/matchit.vim
        " ...
      '';
    };
  };
}
