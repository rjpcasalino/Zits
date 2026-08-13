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
      # reverse search
      bindkey '^R' history-incremental-search-backward
      # Explicitly bind Ctrl+A to beginning of line
      bindkey '^A' beginning-of-line
      # Explicitly bind Ctrl+E to end of line
      bindkey '^E' end-of-line
      # Optional but highly recommended for Xterm: 
      # Fix Ctrl+Left and Ctrl+Right for jumping between words
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
      # Human mode back on, Ryan here. just the classic:
      # set erase character based on terminal emulator
      if [[ "$TERM" == "xterm" ]] || [[ "$TERM" == "xterm-color" ]]; then
          stty erase '^H'
      else
          stty erase '^?'
      fi
      # Set the path for your custom log file
      export CMD_LOG_FILE="$HOME/.advanced_history.log"
      export CMD_LOG_STATE="$HOME/.cmdlogger_active"

      # State variables to pass data between hooks
      typeset -g _cmdlogger_start_time
      typeset -g _cmdlogger_current_cmd

      # The control interface (remains the same)
      cmdlogger() {
          case "$1" in
              start)
                  touch "$CMD_LOG_STATE"
                  echo "Logging enabled. Outputting to $CMD_LOG_FILE" ;;
              stop)
                  rm -f "$CMD_LOG_STATE"
                  echo "Logging disabled." ;;
              *) echo "Usage: cmdlogger {start|stop}" ;;
          esac
      }

      # Hook 1: Runs right before execution
      preexec() {
          if [[ -f "$CMD_LOG_STATE" ]]; then
              _cmdlogger_start_time=$(date +%s)
              _cmdlogger_current_cmd="$1"
          fi
      }

      # Hook 2: Runs immediately after the command finishes
      precmd() {
          # Capture the exit code immediately before any other command runs
          local exit_code=$?

          if [[ -f "$CMD_LOG_STATE" && -n "$_cmdlogger_current_cmd" ]]; then
              local end_time=$(date +%s)
              local duration=$(( end_time - _cmdlogger_start_time ))
              local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

              # Check for specific development environments
              local env_state=""
              if [[ -n "$IN_NIX_SHELL" ]]; then
                  env_state="[nix] "
              fi

              echo "[$timestamp] [Status: $exit_code] [$duration s] $USER $env_state$PWD > $_cmdlogger_current_cmd" >> "$CMD_LOG_FILE"

              # Clear the variable so hitting 'Enter' on an empty prompt doesn't duplicate logs
              _cmdlogger_current_cmd=""
          fi
      }
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
