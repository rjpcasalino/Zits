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
      # Force Emacs keybindings
      bindkey -e
      # Explicitly bind Ctrl+A to beginning of line
      bindkey '^A' beginning-of-line
      # Explicitly bind Ctrl+E to end of line
      bindkey '^E' end-of-line
      # Optional but highly recommended for Xterm: 
      # Fix Ctrl+Left and Ctrl+Right for jumping between words
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
    '';
  };

  # -----------------------------------------------------------
  # THE CYBERDECK PROMPT (1980s Vibe / 2026 Tech)
  # -----------------------------------------------------------
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;

      # The Layout: 
      # [14:05:22] [rjpcasalino@host] // DIR: ~/code // GIT: main [!+?] // NIX: shell
      # >_ 
      format = ''
        $time$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration
        $character
      '';

      # System Clock (Retro log file vibe)
      time = {
        disabled = false;
        time_format = "%H:%M:%S";
        style = "bold bright-black";
        format = "[\\[$time\\]]($style) ";
      };

      # Phosphor Green User & Host
      username = {
        show_always = true;
        style_user = "bold bright-green";
        style_root = "bold bright-red";
        format = "[\\[$user]($style)";
      };

      hostname = {
        ssh_only = false; # Always show for that mainframe feel
        style = "bold bright-green";
        format = "[@$hostname\\]]($style) ";
      };

      # Cyan Directory with Retro Label
      directory = {
        style = "bold bright-cyan";
        format = "[// DIR: $path ]($style)";
        truncation_length = 4;
        truncate_to_repo = false;
      };

      # Magenta Git Status (No Emojis)
      git_branch = {
        style = "bold bright-magenta";
        symbol = ""; # Ditch the modern git icon
        format = "[// GIT: $branch ]($style)";
      };

      # Amber/Yellow Git changes (ASCII symbols only)
      git_status = {
        style = "bold bright-yellow";
        format = "[\\[$all_status$ahead_behind\\]]($style) ";
        conflicted = "X";
        ahead = "↑\${count}";
        behind = "↓\${count}";
        diverged = "↕\${ahead_count} \${behind_count}";
        untracked = "?";
        modified = "!";
        staged = "+";
        deleted = "-";
      };

      # Bright Blue Nix Environment Indicator
      nix_shell = {
        style = "bold bright-blue";
        symbol = "";
        format = "[// NIX: $state( \\($name\\)) ]($style)";
      };

      # Execution Time (Only shows if command takes > 2 seconds)
      cmd_duration = {
        style = "bold bright-black";
        format = "[// TMR: $duration ]($style)";
      };

      # The Blinking Block Cursor Vibe
      character = {
        success_symbol = "[>_](bold bright-green)";
        error_symbol = "[>_](bold bright-red)";
        vimcmd_symbol = "[<_](bold bright-blue)";
      };
    };
  };
}
