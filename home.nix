{ pkgs, ... }:

{
  home.username = "rjpc";
  home.homeDirectory = "/home/rjpc";
  home.packages = with pkgs; [
    age
    arandr
    awscli2
    curl
    cmus
    direnv
    du-dust
    ed
    fd
    feh
    ffmpeg-full
    fortune
    go
    gopls
    grpcui
    jq
    makemkv
    nixpkgs-fmt
    nixpkgs-review
    neofetch
    oneko
    pamixer
    qemu
    rnix-lsp # nix lang server
    redshift
    ripgrep
    rpi-imager
    scrot
    screen
    spotify
    slack
    synergy
    unzip
    wget
    xdg-utils
    xscreensaver
    xorg.xmodmap
    xorg.xev
    xorg.libXft
    zoom-us
  ];

  home.stateVersion = "22.05";

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    shellAliases = {
      ll = "ls -l";
      ".." = "cd ..";
      "..." = "cd ../..";
      "g" = "git";
      "zits" = "sudo nixos-rebuild switch --flake .#zits";
    };
    initExtra = ''
      export GIT_PS1_SHOWDIRTYSTATE=1
      export GIT_PS1_SHOWSTASHSTATE=1
      export GIT_PS1_SHOWCOLORHINTS=1
      export GIT_PS1_SHOWUPSTREAM="auto"
      setopt PROMPT_SUBST
      autoload -U colors && colors
      source $HOME/.git-prompt.sh
      export PS1='%F{magenta}%n%f %B%F{blue}%~%f $(__git_ps1 "(%s) ")%b%# '
    '';
  };

  programs.git = {
    enable = true;
    userName = "rjpc";
    userEmail = "rjpc@rjpc.net";
    aliases = {
      a = "add";
      c = "commit";
      d = "diff";
      f = "fetch";
      s = "status";
      l = "log --graph --decorate --pretty=oneline --abbrev-commit";
      p = "push";
    };
  };

  programs.vim = {
    enable = true;
    plugins = [
      pkgs.vimPlugins.csv-vim
      pkgs.vimPlugins.csv
      pkgs.vimPlugins.lightline-vim
      pkgs.vimPlugins.vim-nix
      pkgs.vimPlugins.matchit-zip
      pkgs.vimPlugins.vim-go
      pkgs.vimPlugins.colorizer
      pkgs.vimPlugins.editorconfig-vim
      pkgs.vimPlugins.vim-terraform
      pkgs.vimPlugins.vim-lsp
    ];
    settings = {
      background = "light";
      mouse = "a";
      number = true;
      tabstop = 8;
    };
    extraConfig = ''
      if !has('gui_running')
        set t_Co=256
      endif
      colorscheme default
      syntax on
      set ruler
      set hlsearch
      set spelllang=en_us
      set paste
      set list
      " a space is required after
      " tab:▸\
      set listchars=eol:¬,tab:▸\ ,trail:·
      set wildmenu
      set wildmode=longest,list,full
      " don't pollute dirs with swap files
      " keep them in one place
      silent !mkdir -p ~/.vim/{backup,swp}/
      set backupdir=~/.vim/backup/
      set directory=~/.vim/swp/
      noremap <F11> :tabprevious<CR>
      noremap <F12> :tabnext<CR>
      "" Nav between buffer windows
      " this should be the ALT or META key
      " i.e, <A-*> or <M-*>
      " but this might clash with cwm alt usage?
      " anyway, use shift instead if one wants by uncommenting:
      "noremap <S-H> <C-W><C-H>
      "noremap <S-J> <C-W><C-J>
      "noremap <S-K> <C-W><C-K>
      "noremap <S-L> <C-W><C-L>
      let g:netrw_preview = 1
      let g:netrw_banner = 1
      let g:netrw_liststyle = 3
      let g:netrw_winsize = 25
      " autocmd adds to the list of autocommands regardless of 
      " whether they are already present
      " so we use augroup to avoid that issue
      augroup vimrc
        autocmd!
        au BufRead,BufNewFile *.md,*.txt,*.man,*.ms setlocal spell
        hi clear SpellBad
        hi SpellBad cterm=underline,bold ctermfg=red
      augroup END
      runtime macros/matchit.vim
    '';
  };
}
