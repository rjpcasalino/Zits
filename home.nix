{ pkgs, ... }:

{
  home.username = "rjpc";
  home.homeDirectory = "/home/rjpc";
  home.packages = [ ];

  home.stateVersion = "22.05";

  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  programs.zsh.initExtra = ''
    export GIT_PS1_SHOWDIRTYSTATE=1
    export GIT_PS1_SHOWSTASHSTATE=1
    export GIT_PS1_SHOWCOLORHINTS=1
    export GIT_PS1_SHOWUPSTREAM="auto"
    setopt PROMPT_SUBST
    autoload -U colors && colors
    source $HOME/.git-prompt.sh
    export PS1='%F{magenta}%n%f %B%F{blue}%~ $(__git_ps1 "(%s) ")%b%f%# '
  '';
}
