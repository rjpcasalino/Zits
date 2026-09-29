{ config, pkgs, lib, ... }:

let
  # Habamax-aligned palette based on system console configuration
  colors = {
    bg         = "1c1c1c"; # color 0
    red        = "af5f5f"; # color 1
    green      = "5faf5f"; # color 2
    yellow     = "af875f"; # color 3
    blue       = "5f87af"; # color 4
    magenta    = "af87af"; # color 5
    cyan       = "5f8787"; # color 6
    fg         = "9e9e9e"; # color 7
    bright_bg  = "767676"; # color 8
  };
in
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Visual UI Dependencies
  environment.systemPackages = with pkgs; [
    foot
    waybar
    wofi
    hyprpaper
    btop
    font-awesome
  ];

  # System-wide Hyprland Configuration
  environment.etc."xdg/hypr/hyprland.conf".text = ''
    # -----------------------------------------------------
    # Monitor Layout & Workspace Assignments (Matching Sway)
    # -----------------------------------------------------
    monitor = HDMI-A-1, 2560x1440@60, 0x0, 1
    monitor = DP-2, 2560x1440@60, 2560x0, 1
    monitor = , preferred, auto, 1

    workspace = 1, monitor:DP-2, default:true
    workspace = 2, monitor:HDMI-A-1, default:true

    # -----------------------------------------------------
    # Default Applications
    # -----------------------------------------------------
    $terminal = foot
    $menu = wofi --show drun

    # -----------------------------------------------------
    # Visual UI & Colors (Habamax Palette)
    # -----------------------------------------------------
    general {
        gaps_in = 4
        gaps_out = 8
        border_size = 2
        col.active_border = rgba(${colors.blue}ff) rgba(${colors.cyan}ff) 45deg
        col.inactive_border = rgba(${colors.bright_bg}aa)
        layout = dwindle
    }

    decoration {
        rounding = 8
        blur {
            enabled = true
            size = 3
            passes = 2
        }
    }

    # -----------------------------------------------------
    # Keybindings (Omarchy Quattro + Sway Defaults)
    # -----------------------------------------------------
    $mainMod = SUPER

    # Primary Terminal Launchers
    bind = $mainMod, Return, exec, $terminal
    bind = $mainMod, Space, exec, $menu
    bind = $mainMod, D, exec, $menu
    bind = $mainMod ALT, Space, exec, wofi --show run

    # Navigation & Focus (Arrows + Vim hjkl)
    bind = $mainMod, left, movefocus, l
    bind = $mainMod, right, movefocus, r
    bind = $mainMod, up, movefocus, u
    bind = $mainMod, down, movefocus, d
    bind = $mainMod, H, movefocus, l
    bind = $mainMod, L, movefocus, r
    bind = $mainMod, K, movefocus, u
    bind = $mainMod, J, movefocus, d

    # Window Swapping
    bind = $mainMod SHIFT, right, swapwindow, r
    bind = $mainMod SHIFT, left, swapwindow, l
    bind = $mainMod SHIFT, H, swapwindow, l
    bind = $mainMod SHIFT, L, swapwindow, r
    bind = $mainMod SHIFT, K, swapwindow, u
    bind = $mainMod SHIFT, J, swapwindow, d

    # Window Management
    bind = $mainMod, W, killactive
    bind = $mainMod, Q, killactive
    bind = $mainMod SHIFT, Q, killactive
    bind = $mainMod, X, killactive
    bind = CTRL ALT, Delete, exit
    bind = $mainMod, T, togglefloating
    bind = $mainMod SHIFT, Space, togglefloating
    bind = $mainMod, O, pin

    # Fullscreen States
    bind = $mainMod, F, fullscreen, 0
    bind = $mainMod ALT, F, fullscreen, 1
    bind = $mainMod CTRL, F, fullscreenstate, 1 1

    # Layouts & Grouping
    bind = $mainMod, G, togglegroup
    bind = $mainMod ALT, G, moveoutofgroup
    bind = $mainMod CTRL, right, changegroupactive, f
    bind = $mainMod CTRL, left, changegroupactive, b

    # TUI Launchers
    bind = $mainMod CTRL, T, exec, $terminal -e btop
    bind = $mainMod CTRL, Return, exec, $terminal -e tmux
    bind = $mainMod SHIFT, D, exec, $terminal -e lazydocker
    bind = $mainMod SHIFT, F, exec, $terminal -e yazi
    bind = $mainMod SHIFT ALT, M, exec, $terminal -e cliamp
    bind = $mainMod CTRL, W, exec, $terminal -e nmtui
    bind = $mainMod CTRL, B, exec, $terminal -e bluetoothctl

    # Workspaces
    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod, 0, workspace, 10

    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5
    bind = $mainMod SHIFT, 6, movetoworkspace, 6
    bind = $mainMod SHIFT, 7, movetoworkspace, 7
    bind = $mainMod SHIFT, 8, movetoworkspace, 8
    bind = $mainMod SHIFT, 9, movetoworkspace, 9
    bind = $mainMod SHIFT, 0, movetoworkspace, 10

    # Mouse Bindings
    bindm = $mainMod, mouse:272, movewindow
    bindm = $mainMod, mouse:273, resizewindow

    # Audio & Media Keys
    binde = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
    binde = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bind  = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bind  = , XF86AudioPlay, exec, playerctl play-pause
    bind  = , XF86AudioNext, exec, playerctl next
    bind  = , XF86AudioPrev, exec, playerctl previous

    # Startup Services
    exec-once = waybar
  '';

  # System-wide Waybar Configuration
  environment.etc."xdg/waybar/config".text = ''
    {
      "layer": "top",
      "position": "top",
      "height": 28,
      "spacing": 4,
      "modules-left": ["hyprland/workspaces", "hyprland/window"],
      "modules-center": ["clock"],
      "modules-right": ["network", "bluetooth", "pulseaudio", "battery"],
      "hyprland/workspaces": {
        "format": "{icon}",
        "format-icons": {
          "active": "●",
          "default": "○"
        }
      },
      "clock": {
        "format": "{:%a %F %I:%M%p}"
      }
    }
  '';

  environment.etc."xdg/waybar/style.css".text = ''
    * {
      font-family: "Noto Sans", "Font Awesome 6 Free";
      font-size: 13px;
      border: none;
      border-radius: 0;
    }

    window#waybar {
      background-color: #${colors.bg};
      color: #${colors.fg};
    }

    #workspaces button {
      padding: 0 5px;
      color: #${colors.bright_bg};
    }

    #workspaces button.active {
      color: #${colors.blue};
    }

    #clock, #battery, #network, #bluetooth, #pulseaudio {
      padding: 0 10px;
      color: #${colors.fg};
    }
  '';

  # Set Ozone Wayland backend system-wide for Chromium/Electron apps
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    TERMINAL = "foot";
  };
}
