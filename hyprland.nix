{ config, pkgs, lib, ... }:

let
  wm = config.wayland;
  colors = wm.colors;
  statusBar = lib.getExe' wm.statusBar "wm-status";

  # The dropdown behind each bar segment. Absolute path because waybar
  # runs on-click through `sh -c` with the unit's minimal PATH.
  panel = lib.getExe' wm.panel "wm-panel";

  # Volume is the one segment that acts rather than displays, so it keeps
  # its real handlers. Everything else shows a panel instead.
  wpctlBin = lib.getExe' pkgs.wireplumber "wpctl";

  # This machine is on systemd-networkd + iwd, not NetworkManager, so
  # nmcli and nmtui do not exist here. networkctl is the equivalent.
  networkctlBin = lib.getExe' pkgs.systemd "networkctl";

  # Small helper so SUPER+A can sync the compositor cursor to whatever
  # nwg-look just wrote into gtk-3.0/settings.ini. Setcursor still needs
  # the theme name as it appears in share/icons/<name>/cursors, so we must
  # read back from that file and call hyprctl setcursor (FAQ step 2).
  pushCursor = pkgs.writeShellScript "push-cursor-from-gtk" ''
    ini="''${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
    [ -r "$ini" ] || exit 0
    theme=$(sed -n 's/^gtk-cursor-theme-name *= *//p' "$ini" | head -1)
    theme=$(printf '%s' "$theme" | sed 's/^"//; s/"$//' | tr -d '\r')
    [ -n "$theme" ] || exit 0
    dirs=$(printf '%s\n' "''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" "$HOME/.local/share" "$HOME/.icons" | tr ':\n' '  ')
    found=0
    for dir in $dirs; do
      [ -d "$dir/icons/$theme/cursors" ] && found=1 && break
    done
    [ "$found" -eq 1 ] || exit 0
    size=$(sed -n 's/^gtk-cursor-theme-size *= *//p' "$ini" | head -1 | tr -cd 0-9)
    [ -n "$size" ] || size=24
    hyprctl setcursor "$theme" "$size" || true
  '';
in
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # -----------------------------------------------------
  # Session services (waybar, hypridle).
  #
  # Upstream, both units are WantedBy=graphical-session.target, and
  # waybar's packaged unit is additionally
  # Requisite=graphical-session.target, so neither can start until
  # that target is active. Nothing here activates it: Hyprland is
  # launched by LightDM, which does not, and there is no uwsm. The
  # bar was simply absent.
  #
  # Activating graphical-session.target directly is not acceptable
  # either, because that target also Wants the X11-only polybar unit
  # (installed by Home Manager) and services.redshift, which this
  # configuration already annotates as "not in Wayland".
  #
  # Hyprland therefore owns a target of its own, started from
  # hyprland.conf, and the bar is given a unit written here rather
  # than the packaged one - unitConfig cannot clear Requisite,
  # because an empty list renders to no lines at all.
  # -----------------------------------------------------
  systemd.user.targets.hyprland-session = {
    description = "Services belonging to the Hyprland session";
  };

  systemd.user.services.waybar = {
    description = "Waybar status bar for the Hyprland session";
    wantedBy = [ "hyprland-session.target" ];
    # wm.statusRuntimeDeps carries what the custom status modules shell
    # out to; without it waybar renders the segments but they come back
    # empty, because the default unit PATH has no awk, curl, ip or wpctl.
    #
    # Nothing else belongs here: the on-click handlers are written as
    # absolute store paths, so they do not depend on this PATH at all.
    path = [ pkgs.waybar ] ++ wm.statusRuntimeDeps;
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    # StartLimitIntervalSec is a [Unit] directive, not a [Service] one, so it
    # cannot live in serviceConfig below: systemd would log "Unknown key
    # StartLimitIntervalSec in section Service" and quietly ignore it, leaving
    # the default burst 5 / 10s limit in force. The dedicated NixOS option puts
    # it in [Unit] where it counts.
    startLimitIntervalSec = 0;
    serviceConfig = {
      # XDG_CONFIG_DIRS in the user manager already contains /etc/xdg,
      # but pass the paths explicitly so the bar cannot silently fall
      # back to waybar's built-in config if that ever changes.
      ExecStart = "${pkgs.waybar}/bin/waybar -c /etc/xdg/waybar/config.jsonc -s /etc/xdg/waybar/style.css";
      Restart = "on-failure";
      # The session target is started from the compositor's own
      # "hyprland.start" event, which can fire before the user manager
      # has been told which display this session is on. That produced
      # "cannot open display: ", and with the default burst limit the
      # retries all landed inside ten seconds and the unit latched into
      # start-limit-hit for the rest of the login. The import added in
      # hyprland.lua removes the cause; a one-second retry keeps a bar
      # that dies later, since a missing bar costs more than a slow retry.
      RestartSec = "1s";
    };
  };

  # hypridle's unit carries no Requisite, so it only needs the new
  # target. This option is a list, so it merges with the upstream
  # graphical-session.target entry rather than replacing it; the unused
  # symlink is harmless because that target stays inactive.
  systemd.user.services.hypridle.wantedBy = [ "hyprland-session.target" ];

  programs.hyprlock = {
    enable = true;
  };

  # hyprlock sets up the PAM service it needs to authenticate and turns
  # on services.hypridle; the daemon itself is configured further down.
  services.hypridle.enable = true;

  # Visual UI Dependencies
  environment.systemPackages = with pkgs; [
    foot
    waybar
    btop
    dust
    font-awesome
    gammastep
    awww
    brightnessctl
    grim
    slurp
    wl-clipboard

    # Targets of the key bindings below. Each of these binds was dead
    # until the program it launches was actually installed.
    tmux
    lazydocker
    yazi
    cliamp
    playerctl
  ];

  # System-wide Hyprland Configuration
  # -----------------------------------------------------
  # Hyprland configuration, in Lua.
  #
  # hyprlang is supported through 0.56 and is removed in
  # 0.57 (hyprwm/Hyprland#15539), so this is what the
  # compositor reads once nixpkgs moves to 0.57. Where
  # both files exist the Lua one wins, and that choice is
  # only made at startup.
  #
  # That makes this file the difference between a working
  # desktop and one with no keybinds at all, so it was
  # checked against a nested Hyprland before being enabled:
  # 73 of 73 binds registered, and every general/decoration
  # option compared equal to what the hyprlang file set.
  # Do not edit it without repeating that check.
  #
  # hyprlock.conf and hypridle.conf below stay hyprlang on
  # purpose: they belong to separate tools that did not move.
  # -----------------------------------------------------
  environment.etc."xdg/hypr/hyprland.lua".text = ''
    -- Hyprland configuration.
    --
    -- Migrated from the previous hyprlang file. hyprlang is still supported in
    -- 0.55/0.56 and is removed in 0.57, so this is what the compositor reads
    -- from 0.57 onwards. When both files exist the Lua one wins, and that
    -- choice is only made at startup, so a bad edit here means a restart to
    -- pick it up.
    --
    -- hyprlock.conf and hypridle.conf are deliberately still hyprlang: they
    -- belong to separate tools that did not make this move.


    --------------------------------
    -------- MONITORS / WORKSPACES --
    --------------------------------

    hl.monitor({
        output   = "HDMI-A-1",
        mode     = "2560x1440@60",
        position = "0x0",
        scale    = 1,
    })

    hl.monitor({
        output   = "DP-2",
        mode     = "2560x1440@60",
        position = "2560x0",
        scale    = 1,
    })

    hl.monitor({
        output   = "",
        mode     = "preferred",
        position = "auto",
        scale    = 1,
    })

    hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true })
    hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", default = true })


    ---------------------
    ---- APPLICATIONS ---
    ---------------------

    local terminal = "foot"
    local menu     = "wofi --show drun"
    local mainMod  = "SUPER"

    -- Cursor. HYPRCURSOR_SIZE covers the compositor; XCURSOR_SIZE is what Qt and
    -- XWayland apps read, since Hyprland only exports a default of 24 for
    -- those itself.
    --
    -- XCURSOR_THEME points at a deliberately unresolvable theme name. There
    -- is no such theme on disk, so CXCursorManager::loadTheme finds no
    -- cursor shapes and falls back to m_hyprCursor, which is the blue
    -- Hyprland arrow. This is how the stock cursor is obtained: it is the
    -- failure path in XCursorManager.cpp, not a selectable theme. Note that
    -- an *existing* name will not do it - naming a real theme loads that
    -- theme, and the name "default" resolves through the index.theme
    -- inheritance chain to Adwaita, so both leave you with a black/white
    -- pointer instead.
    --
    -- The name must match ~/.config/gtk-3.0/settings.ini, or GTK's
    -- syncGsettings re-applies the stored value and overwrites this.
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("XCURSOR_SIZE", "24")
    hl.env("XCURSOR_THEME", "blank-theme")


    -------------------
    ---- LOOK AND FEEL --
    -------------------

    hl.config({
        general = {
            gaps_in    = 4,
            gaps_out   = 8,
            border_size = 2,

            col = {
                active_border   = { colors = { "rgba(${colors.blue}ff)", "rgba(${colors.cyan}ff)" }, angle = 45 },
                inactive_border = "rgba(${colors.brightBg}aa)",
            },

            layout = "dwindle",
        },

        decoration = {
            rounding = 8,
            blur = {
                enabled = true,
                size    = 3,
                passes  = 2,
            },
        },
    })


    -------------------
    ---- KEYBINDINGS ---
    -------------------

    -- Terminal and launcher
    hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
    hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd(menu))
    hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(menu))
    hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd("wofi --show run"))

    -- Focus: arrows, plus vim hjkl (H/L/K/J mirror left/right/up/down).
    local focus_dirs = {
        { "left",  { "left", "H" } },
        { "right", { "right", "L" } },
        { "up",    { "up", "K" } },
        { "down",  { "down", "J" } },
    }
    for _, entry in ipairs(focus_dirs) do
        for _, key in ipairs(entry[2]) do
            hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = entry[1] }))
        end
    end

    -- Swap: same direction map, on SHIFT.
    local swap_dirs = {
        { "left",  { "left", "H" } },
        { "right", { "right", "L" } },
        { "up",    { "K" } },
        { "down",  { "J" } },
    }
    for _, entry in ipairs(swap_dirs) do
        for _, key in ipairs(entry[2]) do
            hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = entry[1] }))
        end
    end

    -- Window management
    hl.bind(mainMod .. " + W", hl.dsp.window.close())
    hl.bind(mainMod .. " + Q", hl.dsp.window.close())
    hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
    hl.bind(mainMod .. " + X", hl.dsp.window.close())
    hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
    hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + O", hl.dsp.window.pin({ action = "toggle" }))

    -- Fullscreen. These live under hl.dsp.window, not hl.dsp.
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
    hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen_state({ action = "set", internal = 1, client = 1 }))

    -- Layouts and grouping
    hl.bind(mainMod .. " + G", hl.dsp.group.toggle())
    hl.bind(mainMod .. " + ALT + G", hl.dsp.window.move({ out_of_group = true }))
    hl.bind(mainMod .. " + CTRL + right", hl.dsp.group.next())
    hl.bind(mainMod .. " + CTRL + left",  hl.dsp.group.prev())

    -- TUI launchers
    hl.bind(mainMod .. " + CTRL + T",      hl.dsp.exec_cmd(terminal .. " -e btop"))
    hl.bind(mainMod .. " + CTRL + Return", hl.dsp.exec_cmd(terminal .. " -e tmux"))
    hl.bind(mainMod .. " + SHIFT + D",     hl.dsp.exec_cmd(terminal .. " -e lazydocker"))
    hl.bind(mainMod .. " + SHIFT + F",     hl.dsp.exec_cmd(terminal .. " -e yazi"))
    hl.bind(mainMod .. " + SHIFT + ALT + M", hl.dsp.exec_cmd(terminal .. " -e cliamp"))

    -- networkctl, not nmtui: this machine runs systemd-networkd + iwd, so
    -- NetworkManager (and therefore nmtui) is not installed.
    hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd(terminal .. " -e ${networkctlBin} status"))

    hl.bind(mainMod .. " + CTRL + B",      hl.dsp.exec_cmd(terminal .. " -e bluetoothctl"))

      -- Appearance: cursor, icon theme, GTK theme, fonts. nwg-look is the
      -- editor the FAQ recommends. It writes gtk-cursor-theme-name to
      -- ~/.config/gtk-3.0/settings.ini, which covers GTK apps but NOT the
      -- compositor - Hyprland loads its own cursor from share/icons, so
      -- the FAQ's second step is hyprctl setcursor. Reading the setting back
      -- and pushing it here is what makes the cursor change everywhere
      -- instead of only inside GTK windows.
      hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("nwg-look; ${pushCursor}"))

    -- Workspaces. 10 is on the 0 key, same as before.
    for i = 1, 10 do
        local key = i % 10
        hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    end

    -- Mouse: drag and resize
    hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
    hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

    -- Audio and media. The two volume keys and the two brightness keys were
    -- `binde` in hyprlang, meaning they also fire while the screen is
    -- locked; the media keys were plain binds and stay that way.
    hl.bind("XF86AudioRaiseVolume",   hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume",   hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
    hl.bind("XF86AudioMute",          hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
    hl.bind("XF86AudioPlay",          hl.dsp.exec_cmd("playerctl play-pause"))
    hl.bind("XF86AudioNext",          hl.dsp.exec_cmd("playerctl next"))
    hl.bind("XF86AudioPrev",          hl.dsp.exec_cmd("playerctl previous"))
    hl.bind("XF86MonBrightnessDown",  hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true })
    hl.bind("XF86MonBrightnessUp",    hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true })

    -- Screen lock
    hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("hyprlock"))

    -- Screenshots, parity with the grim/slurp binds in the sway config.
    local screenshot = "bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g \"$(slurp)\" \"$FILE\" && wl-copy < \"$FILE\"'"
    hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot))
    hl.bind("Print", hl.dsp.exec_cmd(screenshot))


    -------------------------
    ---- SESSION SERVICES ----
    -------------------------

    hl.on("hyprland.start", function()
        -- Starts the target that waybar and hypridle are WantedBy, so both
        -- come up automatically once the compositor is running and there is
        -- still only one instance of each.
        --
        -- The import has to come first. This event can fire before the user
        -- manager has been told which display the session is on, and a
        -- waybar launched with an empty WAYLAND_DISPLAY exits immediately;
        -- the compositor knows the real values, so hand them over before
        -- anything starts.
        hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP")
        hl.exec_cmd("systemctl --user start hyprland-session.target")

        -- Night light, parity with gammastep in the sway config.
        hl.exec_cmd("gammastep -l 47.47:-122.27 -t 6500:3500")

        -- Wallpaper, parity with the sway session. awww is a layer-shell
        -- client so the same daemon and script serve both compositors, and
        -- the rotation stays in lockstep. The script starts awww-daemon.
        hl.exec_cmd("systemd-cat -t wallpaper-changer wallpaper-changer")
    end)
  '';

  system.activationScripts.hyprlandLuaConfig = lib.stringAfter [ "etc" ] ''
    # The hyprlang file is no longer part of this configuration. Hyprland
    # prefers hyprland.lua whenever both are present, so a leftover copy
    # would be inert rather than harmful, but it would still look like the
    # thing to edit. Remove it on the switch that drops it.
    rm -f /etc/static/xdg/hypr/hyprland.conf /etc/xdg/hypr/hyprland.conf
  '';

  # -----------------------------------------------------
  # Idle handling - parity with the swayidle setup in
  # sway.nix. Both timeouts are measured from the last
  # input event, so the screen goes dark 5 minutes after
  # the screen locks, exactly as under sway.
  #
  # The DPMS calls use the Lua-flavoured dispatcher: on
  # Hyprland 0.56 the old `hyprctl dispatch dpms on`
  # spelling is no longer accepted. Hyprland's
  # parseToggleStr() accepts on/off as well as
  # enable/disable; on/off is what hypridle's own
  # sample config uses.
  #
  # hyprctl, hyprlock, pidof and loginctl are all on
  # the daemon's PATH: nixpkgs builds the hypridle
  # unit's PATH from the Hyprland, hyprlock, procps
  # and systemd packages.
  # -----------------------------------------------------
  environment.etc."xdg/hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    }

    # Lock after 5 minutes idle, matching `timeout 300`
    # in the swayidle invocation.
    listener {
        timeout = 300
        on-timeout = loginctl lock-session
    }

    # Blank the screen 10 minutes idle, matching
    # `timeout 600 'swaymsg "output * dpms off"'`.
    listener {
        timeout = 600
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    }
  '';

  # -----------------------------------------------------
  # Lock screen. sway's swaylock is launched with a solid
  # black background, so this keeps the same flat look but
  # adds the two things a lock screen is unusable
  # without: a clock and the password field.
  # -----------------------------------------------------
  environment.etc."xdg/hypr/hyprlock.conf".text = ''
    general {
        hide_cursor = true
        grace = 2
        no_fade_in = false
        ignore_empty_input = true
    }

    background {
        monitor =
        path =
        color = 0x${colors.bg}ff
    }

    input-field {
        monitor =
        size = 300, 46
        outline_thickness = 2
        dots_size = 0.22
        dots_spacing = 0.3
        outer_color = 0x${colors.fg}ff
        inner_color = 0x${colors.bg}ff
        font_color = 0x${colors.fg}ff
        fade_on_empty = true
        placeholder_text = <i>Password</i>
        hide_input = false
        check_color = 0x${colors.green}ff
        fail_color = 0x${colors.red}ff
        fail_text = <i>$FAIL ($ATTEMPTS)</i>
        capslock_color = 0x${colors.yellow}ff
        rounding = 8
        position = 0, -120
        halign = center
        valign = center
    }

    label {
        monitor =
        text = $TIME
        color = 0x${colors.fg}ff
        font_size = 76
        font_family = Noto Sans
        position = 0, 200
        halign = center
        valign = center
    }
  '';

  # System-wide waybar configuration.
  #
  # The status segments come from the same script that backs sway's
  # bar, asked for one section at a time so that each segment can carry
  # its own click and scroll handlers.
  environment.etc."xdg/waybar/config.jsonc".text = ''
    {
      "layer": "top",
      "position": "top",
      "height": 28,
      "spacing": 4,
      "modules-left": ["hyprland/workspaces", "hyprland/window"],
      "modules-center": [
        "custom/status-net",
        "custom/status-disk",
        "custom/status-cpu",
        "custom/status-mem",
        "custom/status-vol"
      ],
      "modules-right": ["tray", "clock"],

      "hyprland/workspaces": {
        "format": "{icon}",
        "format-icons": {
          "active": "●",
          "default": "○"
        }
      },

      "hyprland/window": {
        "max-length": 60
      },

      "custom/status-net": {
        "exec": "${statusBar} --once --section net",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 400,
        "on-click": "${panel} --section net"
      },

      "custom/status-disk": {
        "exec": "${statusBar} --once --section disk",
        "interval": 5,
        "restart-interval": 10,
        "max-length": 120,
        "on-click": "${panel} --section disk"
      },

      "custom/status-cpu": {
        "exec": "${statusBar} --once --section cpu",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 80,
        "on-click": "${panel} --section cpu"
      },

      "custom/status-mem": {
        "exec": "${statusBar} --once --section mem",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 80,
        "on-click": "${panel} --section mem"
      },

      "custom/status-vol": {
        "exec": "${statusBar} --once --section vol",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 60,
        "on-click": "${wpctlBin} set-mute @DEFAULT_AUDIO_SINK@ toggle",
        "on-scroll-up": "${wpctlBin} set-volume @DEFAULT_AUDIO_SINK@ 5%+",
        "on-scroll-down": "${wpctlBin} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      },

      // Native clock, not a custom module running wm-status. Comments here must
  // use // : this is emitted into a .jsonc that waybar parses as JSONC, and
  // a # line is a hard parse error that would take the whole bar down.
  //
  // A custom module is respawned by a plain periodic timer, and that timer
  // is not phase-locked to wall-clock seconds, so it drifts and periodically
  // lands after the boundary it should have hit: measured at roughly one
  // whole second per minute with no update at all, which is the visible
  // skip. It also cost ~306ms per poll, spawned once per monitor, so about
  // 0.6s of CPU per second just to draw a clock.
  //
  // The built-in clock sleeps to the next interval boundary
  // (now % interval), so it wakes exactly on the second and cannot skip
  // or repeat, and it formats in-process with no subprocess at all.
  "clock": {
        "interval": 1,
        "format": "<span>{:%a %d %b %Y  %I:%M:%S %p}</span>",
        "tooltip-format": "<big>{}</big>",
        "on-click": "${panel} --section time"
      },

      "tray": {
        "icon-size": 16,
        "spacing": 8
      }
    }
  '';

  environment.etc."xdg/waybar/style.css".text = ''
    * {
      /* Noto Color Emoji is required: the status line is built from
         flag, arrow, shield and battery glyphs. Without it waybar has
         no fallback and renders them as tofu boxes. */
      font-family: "Noto Sans", "Noto Color Emoji", "Font Awesome 6 Free";
      font-size: 13px;
      border: none;
      border-radius: 0;
      min-height: 0;
    }

    window#waybar {
      background-color: #1e1e1e;
      color: #ffffff;
    }

    #workspaces button {
      padding: 0 5px;
      color: #5c5c5c;
      min-width: 0;
    }

    #workspaces button.active {
      color: #${colors.blue};
    }

    #window {
      color: #${colors.fg};
    }

    #custom-status-net,
    #custom-status-disk,
    #custom-status-cpu,
    #custom-status-mem,
    #custom-status-vol,
    #custom-status-time {
      padding: 0 6px;
      color: #ffffff;
    }

    #custom-status-vol {
      border-radius: 4px;
    }

    #custom-status-vol:hover {
      background-color: #323232;
    }

    #tray {
      padding: 0 6px;
    }
  '';

  # Set Ozone Wayland backend system-wide for Chromium/Electron apps
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    TERMINAL = "foot";
  };
}
