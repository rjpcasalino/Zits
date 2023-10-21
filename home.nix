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
  };
  programs.vim = {
    enable = true;
  };
}
