{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 10000;
    histFile = "$HOME/.zsh_history";

    setOptions = [
      "HIST_IGNORE_ALL_DUPS"
      "HIST_FIND_NO_DUPS"
      "HIST_REDUCE_BLANKS"
    ];

    shellAliases = {
      # ... (Keep all your excellent aliases here)
      ".." = "cd ..";
      "..." = "cd ../..";
      "dc" = "docker compose";
      "ddie" = "docker system prune -a --volumes";
      "de" = "docker exec -it";
      "dnin" = "docker network inspect";
      "dnls" = "docker network ls";
      "dps" = "docker ps";
      "fd" = "fd -c never";
      "g" = "git";
      "ll" = "ls -l";
      "ls" = "ls --color=auto";
      "nd" = "nix develop";
      "zits" = "sudo nixos-rebuild switch --flake .#zits";
    };

    interactiveShellInit = ''
      eval "$(direnv hook zsh)"
      # Force Vim keybindings (human edit)
      bindkey -v
      # Explicitly bind Ctrl+A to beginning of line
      bindkey '^A' beginning-of-line
      # Explicitly bind Ctrl+E to end of line
      bindkey '^E' end-of-line
      # Optional but highly recommended for Xterm: 
      # Fix Ctrl+Left and Ctrl+Right for jumping between words
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
      # Human mode back on, Ryan here. just the classic:
      stty erase ^H
    '';
  };

  # -----------------------------------------------------------
  # MIDNIGHT 2026 PROMPT (Cool Soft Black / Muted Pastels)
  # -----------------------------------------------------------
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;

      format = ''
        $time$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration
        $character
      '';

      # System Clock (Muted slate - visually recedes)
      time = {
        disabled = false;
        time_format = "%H:%M:%S";
        style = "bold #68687a";
        format = "[\\[$time\\]]($style) ";
      };

      # Muted Mint User & Host
      username = {
        show_always = true;
        style_user = "bold #8abf9c";
        style_root = "bold #d97c8a"; # Muted rose for root
        format = "[\\[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "bold #8abf9c";
        format = "[@$hostname\\]]($style) ";
      };

      # Soft Cyan Directory
      directory = {
        style = "bold #78b5ba";
        format = "[\\[ $path \\]]($style) ";
        truncation_length = 4;
        truncate_to_repo = false;
      };

      # Dusty Lavender Git Branch
      git_branch = {
        style = "bold #b893ce";
        symbol = "";
        format = "[{ $branch }]($style)";
      };

      # Soft Gold Git changes
      git_status = {
        style = "bold #d4b47b";
        format = " [\\[$all_status$ahead_behind\\]]($style) ";
        conflicted = "X";
        ahead = "↑\${count}";
        behind = "↓\${count}";
        diverged = "↕\${ahead_count} \${behind_count}";
        untracked = "?";
        modified = "!";
        staged = "+";
        deleted = "-";
      };

      # Powder Blue Nix Environment
      nix_shell = {
        style = "bold #7e9cd8";
        symbol = "";
        format = "[\\( nix: $state \\)]($style) ";
      };

      # Execution Time
      cmd_duration = {
        style = "bold #68687a";
        format = "[~ $duration]($style) ";
      };

      # Cursor Vibe
      character = {
        success_symbol = "[>_](#8abf9c)";
        error_symbol = "[>_](#d97c8a)";
        vimcmd_symbol = "[<_](#7e9cd8)";
      };
    };
  };
}
