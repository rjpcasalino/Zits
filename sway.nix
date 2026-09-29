{ config, pkgs, lib, inputs, ... }:

let
  wm = config.wayland;

  # Copy a script out of the config tree into the store, executable,
  # keeping whatever interpreter its shebang declares. Used instead of
  # dropping files into /etc so the session always runs the version
  # belonging to the current system closure.
  installScript =
    name: path:
    pkgs.runCommand name { } ''
      install -Dm755 ${path} $out/bin/${name}
    '';

  swayWindowSwitcher = installScript "sway-window-switcher" ./sway-window-switcher.py;
  wallpaperChanger = wm.wallpaperChanger;
in

{
  # Wayland / Sway setup #
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      foot
      swaylock
      swayidle
      swaybg
      wl-clipboard
      grim
      slurp
      mako
      qt5.qtwayland
      qt6.qtwayland
      gammastep
      mpvpaper
      awww
    ] ++ [ wm.wofi wm.nwgDock wm.statusBar ] ++ wm.statusRuntimeDeps;
  };

  # Direct system /etc/sway/config to use /etc/nixos/sway.conf
  environment.etc."sway/config".text = ''
    # Sway configuration file tracked in /etc/nixos/sway.conf

    ### Stop X11-only services like polybar on Wayland startup
    exec systemctl --user stop polybar.service
    exec pkill polybar

    # Monitor layout
    output HDMI-A-1 resolution 2560x1440  position 0,0
    output DP-2 resolution 2560x1440  position 2560,0

    # Workspaces
    workspace 1 output DP-2
    workspace 2 output HDMI-A-1

    ### Variables
    set $mod Mod4
    set $left h
    set $down j
    set $up k
    set $right l
    set $term foot
    set $menu wofi --show drun

    ### Night Light / Redshift Alternative (Gammastep)
    exec gammastep -l 47.47:-122.27 -t 6500:3500

    ### Custom Wallpaper Daemon Auto-Start
    exec systemd-cat -t wallpaper-changer ${wallpaperChanger}

    ### nwg-dock. The stylesheet is baked into the wrapper in
    ### wm-common.nix, so no symlink into ~/.config is needed.
    exec nwg-dock -p bottom -mb 10 -i 48 -o DP-2

    ### Key bindings
    bindsym Control+$mod+1 move scratchpad; scratchpad show
    bindsym $mod+Shift+equal floating disable
    bindsym $mod+Shift+plus floating disable
    bindsym $mod+Return exec $term
    bindsym Control+$mod+Return exec wofi --show run
    bindsym $mod+Shift+q kill
    bindsym $mod+d exec $menu
    floating_modifier $mod normal
    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'

    # Window & Workspace Tabbing / Cycling (cwm window-cycle & group-cycle):
    bindsym Alt+Tab focus next
    bindsym Alt+Shift+Tab focus prev
    bindsym $mod+Tab focus next
    bindsym $mod+Shift+Tab focus prev
    bindsym Control+Alt+Tab workspace next
    bindsym Control+Alt+Shift+Tab workspace prev
    bindsym Control+$mod+Tab workspace next
    bindsym Control+$mod+Shift+Tab workspace prev

    # cwm Window Management Shortcuts:
    bindsym $mod+w exec ${swayWindowSwitcher}
    bindsym Mod1+w exec ${swayWindowSwitcher}
    bindsym Control+$mod+h move scratchpad
    bindsym $mod+u scratchpad show
    bindsym $mod+m fullscreen toggle
    bindsym $mod+x kill

    # Moving around:
    bindsym $mod+$left focus left
    bindsym $mod+$down focus down
    bindsym $mod+$up focus up
    bindsym $mod+$right focus right
    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right

    bindsym $mod+Shift+$left move left
    bindsym $mod+Shift+$down move down
    bindsym $mod+Shift+$up move up
    bindsym $mod+Shift+$right move right
    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right

    # Workspaces:
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+0 workspace number 10

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9
    bindsym $mod+Shift+0 move container to workspace number 10

    # Layout stuff:
    bindsym $mod+b splith
    bindsym $mod+v splitv
    bindsym $mod+s layout stacking
    bindsym $mod+t layout tabbed
    bindsym $mod+e layout toggle split
    bindsym $mod+f fullscreen
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle
    bindsym $mod+a focus parent

    for_window [app_id="foot"] floating enable

    # Scratchpad:
    bindsym $mod+Shift+minus move scratchpad
    bindsym $mod+minus scratchpad show

    # Resizing containers:
    mode "resize" {
        bindsym $left resize shrink width 10px
        bindsym $down resize grow height 10px
        bindsym $up resize shrink height 10px
        bindsym $right resize grow width 10px
        bindsym Left resize shrink width 10px
        bindsym Down resize grow height 10px
        bindsym Up resize shrink height 10px
        bindsym Right resize grow width 10px
        bindsym Shift+$left resize shrink width 25px
        bindsym Shift+$down resize grow height 25px
        bindsym Shift+$up resize shrink height 25px
        bindsym Shift+$right resize grow width 25px
        bindsym Shift+Left resize shrink width 25px
        bindsym Shift+Down resize grow height 25px
        bindsym Shift+Up resize shrink height 25px
        bindsym Shift+Right resize grow width 25px
        bindsym Return mode "default"
        bindsym Escape mode "default"
    }
    bindsym $mod+r mode "resize"

    # Utilities:
    bindsym --locked XF86AudioMute exec wpctl set-mute \@DEFAULT_AUDIO_SINK@ toggle
    bindsym --locked XF86AudioLowerVolume exec wpctl set-volume \@DEFAULT_AUDIO_SINK@ 5%-
    bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume \@DEFAULT_AUDIO_SINK@ 5%+

    bindsym --locked XF86AudioPlay exec playerctl play-pause
    bindsym --locked XF86AudioPause exec playerctl play-pause
    bindsym --locked XF86AudioPrev exec playerctl previous
    bindsym --locked XF86AudioNext exec playerctl next
    bindsym --locked XF86AudioStop exec playerctl stop

    bindsym --locked XF86MonBrightnessDown exec brightnessctl set 5%-
    bindsym --locked XF86MonBrightnessUp exec brightnessctl set 5%+

    bindsym $mod+Shift+4 exec bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"'
    bindsym Print exec bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"'

    # swayidle setup
    exec swayidle -w \
        timeout 300 'swaylock -f -c 000000' \
        timeout 600 'swaymsg "output * dpms off"' \
        resume 'swaymsg "output * dpms on"' \
        before-sleep 'swaylock -f -c 000000'

    # Status Bar:
    bar {
        position top
        status_command ${lib.getExe' wm.statusBar "wm-status"} --watch

        # The status line emits pango markup so its segments are
        # coloured; the same script backs the Hyprland bar.
        pango_markup enabled

        colors {
            statusline #ffffff
            background #1e1e1e
            inactive_workspace #32323200 #32323200 #5c5c5c
        }
    }
  '';

  # The window switcher, wallpaper daemon and status line are all
  # referenced from the store above, so no scripts are written to /etc.

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
