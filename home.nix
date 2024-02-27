{ lib, pkgs, ... }:

{
  home.username = "rjpc";
  home.homeDirectory = "/home/rjpc";
  home.packages = with pkgs; [
    age
    arandr
    awscli2
    bc
    curl
    deploy-rs
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
    makemkv
    microsoft-edge
    neofetch
    nixpkgs-fmt
    nixpkgs-review
    nodejs_18 # for copolit-vim
    oneko
    opentofu
    opera
    pamixer
    qemu
    rnix-lsp # nix lang server
    rpi-imager
    screen
    scrot
    slack
    synergy
    unzip
    wget
    xdg-utils
    xorg.libXft
    xorg.xev
    xorg.xmodmap
    xscreensaver
    zathura
    zoom-us
  ];

  home.stateVersion = "22.05";

  home.sessionVariables = {
    EDITOR = "vim";
  };

  programs.home-manager.enable = true;

  programs.chromium.enable = true;

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    history = {
      size = 20000;
      save = 20000;
      ignoreAllDups = true;
      share = true;
    };
    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      "dc" = "docker compose";
      "ddie" = "docker system prune -a --volumes";
      "de" = "docker exec -it";
      "dnin" = "docker network inspect";
      "dnls" = "docker network ls";
      "dps" = "docker ps";
      "fd" = "fd -c never"; # never use color output on fd
      "g" = "git";
      "ll" = "ls -l";
      "ls" = "ls --color=auto";
      "nd" = "nix develop";
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
      eval "$(direnv hook zsh)"
      bindkey -e
      if [[ "$SSH_TTY" ]]; then
        export PS1='%F{#C600E8}SSH on %m%f %F{magenta}%n%f %B%F{red}%~%f $(__git_ps1 "(%s) ")%b%# '
      else
        export PS1='%F{magenta}%n%f %B%F{blue}%~%f $(__git_ps1 "(%s) ")%b%# '
      fi;
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
      pu = "push";
    };
  };

  programs.jq = {
    enable = true;
    colors = {
      arrays = "1;35";
      false = "0;31";
      null = "1;30";
      numbers = "0;36";
      objects = "1;37";
      strings = "0;33";
      true = "0;32";
    };
  };

  programs.ripgrep.enable = true;

  programs.vim = {
    enable = true;
    #plugins =  builtins.attrValues {
    #  inherit (pkgs.vimPlugins)
    #  colorizer
    #  copilot-vim
    #  csv-vim
    #  csv
    #  lightline-vim
    #  matchit-zip
    #  #vim-go
    #  vim-nix
    #  vim-terraform
    #  vim-lsp;
    #};
    plugins = with pkgs.vimPlugins; [
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
    settings = {
      background = "light";
      mouse = "a";
      number = true;
      tabstop = 4;
    };
    extraConfig = ''
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
      noremap <F11> :tabprevious<CR>
      noremap <F12> :tabnext<CR>
      augroup vimrc
        autocmd!
        au BufRead,BufNewFile *.tex,*.md,*.txt,*.man,*.ms setlocal spell
        hi clear SpellBad
        hi SpellBad cterm=underline,bold ctermfg=red
      augroup END
      runtime macros/matchit.vim
    '';
  };
  services.polybar = {
    enable = true;
    config = "/home/rjpc/polybar-scripts/polybar/config.ini";
    script = "polybar zits &";
  };
  systemd.user.services.polybar = {
    Install.WantedBy = [ "graphical-session.target" ];
    # FIXME—this is trash
    Service.Environment = lib.mkForce "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/rjpc/bin";
  };
}
