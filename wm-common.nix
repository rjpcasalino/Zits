# Shared configuration for the Wayland compositors (sway, Hyprland).
#
# Anything both compositors need - the status line, the launcher theme,
# the colour palette - lives here so the two sessions cannot drift apart.
{ config, pkgs, lib, ... }:

let
  # The same colours the console is configured with, kept in one place
  # so the bars, the launcher and the borders all agree.
  colors = {
    bg = "1c1c1c";
    red = "af5f5f";
    green = "5faf5f";
    yellow = "af875f";
    blue = "5f87af";
    magenta = "af87af";
    cyan = "5f8787";
    fg = "9e9e9e";
    brightBg = "767676";
  };

  # status-line.sh reads its palette from the environment so the same
  # file stays runnable outside of Nix for debugging. writeTextFile with
  # an explicit destination is used instead of writeShellScriptBin so the
  # result lands at $out/bin/wm-status and stays syntax-checked by the
  # build (lib.getExe' resolves correctly).
  statusScript = pkgs.writeTextFile {
    name = "wm-status";
    destination = "/bin/wm-status";
    executable = true;
    text = "#!${pkgs.bash}/bin/bash\n" + ''
      export WM_C_BG="#${colors.bg}"
      export WM_C_FG="#${colors.fg}"
      export WM_C_DIM="#${colors.brightBg}"
      export WM_C_BLUE="#${colors.blue}"
      export WM_C_CYAN="#${colors.cyan}"
      export WM_C_GREEN="#${colors.green}"
      export WM_C_YELLOW="#${colors.yellow}"
      export WM_C_RED="#${colors.red}"
      export WM_C_MAGENTA="#${colors.magenta}"
    '' + builtins.readFile ./status-line.sh;
    checkPhase = ''
      ${pkgs.stdenv.shellDryRun} $out/bin/wm-status

      # Run every section against exactly the PATH a unit provides -
      # nothing else, so a dependency that is missing from
      # statusRuntimeDeps cannot be silently satisfied by the build
      # environment. A segment whose command is absent does not fail
      # loudly, it just renders empty, so without this the breakage
      # would only surface as a blank part of the bar at runtime.
      export PATH="${statusCheckPath}/bin"
      export XDG_RUNTIME_DIR="$TMPDIR/wm-status-check"
      mkdir -p "$XDG_RUNTIME_DIR"

      missing=$(
        for section in net disk cpu mem vol time; do
          $out/bin/wm-status --once --section "$section" 2>&1 >/dev/null || true
        done
        $out/bin/wm-status --once 2>&1 >/dev/null || true
        grep -oE '[A-Za-z0-9_.-]+: command not found' || true
      )

      if [ -n "$missing" ]; then
        echo "wm-status is missing runtime dependencies:" >&2
        echo "$missing" | sort -u >&2
        echo "Add them to statusRuntimeDeps in wm-common.nix." >&2
        exit 1
      fi
    '';
  };

  # The dropdown shown when a bar segment is clicked. Same shape as
  # statusScript: an explicit destination under $out/bin so lib.getExe
  # resolves, and a checkPhase so a panel that renders nothing fails the
  # build rather than surfacing as a blank popup at runtime.
  panelScript = pkgs.writeTextFile {
    name = "wm-panel";
    destination = "/bin/wm-panel";
    executable = true;
    text = "#!${pkgs.bash}/bin/bash\n" + ''
      export WM_C_BG="#${colors.bg}"
      export WM_C_FG="#${colors.fg}"
      export WM_C_DIM="#${colors.brightBg}"
      export WM_C_BLUE="#${colors.blue}"
      export WM_C_CYAN="#${colors.cyan}"
      export WM_C_GREEN="#${colors.green}"
      export WM_C_YELLOW="#${colors.yellow}"
      export WM_C_RED="#${colors.red}"

      # wofi and dust are resolved at build time. The panels call them by
      # bare name, so they have to be on PATH here as well as in the
      # unit, and the check below runs with the unit's PATH to prove it.
      export PATH="${panelWofi}/bin:${pkgs.dust}/bin:${pkgs.util-linux}/bin:${statusCheckPath}/bin"
      export WM_PANEL_WOFI="${panelWofi}/bin/wofi"
    '' + builtins.readFile ./status-panel.sh;

    checkPhase = ''
      runHook preCheck

      # The script's own PATH is baked into its shebang preamble, which
      # only applies once it is executed; the build environment is
      # separate. Reuse the same PATH here so the check exercises exactly
      # what the session will get.
      export PATH="${panelWofi}/bin:${pkgs.dust}/bin:${pkgs.util-linux}/bin:${statusCheckPath}/bin"

      # Every panel must produce pango markup with real content. A panel
      # that silently renders nothing is the failure mode that matters
      # here: a click would open an empty window that looks like the
      # handler is broken, which is exactly how the earlier bcal/nmcli
      # mix-up went unnoticed.
      # Rendered text must not be stored in `out`: that is the build's
      # output path, and overwriting it breaks every later invocation and
      # the final install. (This exact mistake has now been made twice.)
      for section in net disk cpu mem time; do
        rendered=$("$out/bin/wm-panel" --section "$section" --list 2>/dev/null)
        if [ -z "$rendered" ]; then
          echo "wm-panel: section $section rendered nothing" >&2
          exit 1
        fi
        if ! printf '%s' "$rendered" | grep -q '<span foreground='; then
          echo "wm-panel: section $section produced no markup" >&2
          printf '%s\n' "$rendered" | head -5 >&2
          exit 1
        fi
        if printf '%s' "$rendered" | grep -q 'command not found'; then
          echo "wm-panel: section $section is missing a runtime dependency" >&2
          exit 1
        fi
        echo "ok    $section"
      done

      # The popup has to be wired to the themed wofi, not to a bare one.
      if ! $out/bin/wm-panel --section net --dry-run 2>/dev/null | grep -q 'wofi'; then
        echo "wm-panel: --dry-run did not print a wofi command line" >&2
        exit 1
      fi

      runHook postCheck
    '';
  };

  # Commands status-line.sh shells out to. They are all in
  # environment.systemPackages, so an interactive shell or a compositor
  # session finds them, but a systemd unit's default PATH is only
  # coreutils, findutils, gnugrep, gnused and systemd - not enough. Any
  # unit that runs the status script has to add these, or the net, disk
  # and volume segments silently come back empty.
  statusRuntimeDeps =
    with pkgs;
    [
      gawk
      curl
      iproute2
      wireplumber
      procps
    ];

  # The PATH a nixpkgs systemd user unit gets by default: coreutils,
  # findutils, gnugrep, gnused and systemd. Deliberately not enough on
  # its own for the status script.
  statusUnitDefaultPath =
    let
      inherit (pkgs) coreutils findutils gnugrep gnused systemd;
    in
    pkgs.buildEnv {
      name = "wm-status-unit-default-path";
      paths = [
        coreutils
        findutils
        gnugrep
        gnused
        systemd
      ];
    };

  # Exactly what a unit gets once statusRuntimeDeps is added, which is
  # what the check below exercises.
  statusCheckPath = pkgs.buildEnv {
    name = "wm-status-check-path";
    paths = statusRuntimeDeps ++ [ statusUnitDefaultPath ];
  };

  # Launcher theme, previously defined inside sway.nix and therefore
  # unavailable to the Hyprland session.
  wofiStyle = pkgs.writeText "wofi-style.css" ''
    window {
        margin: 0px;
        padding: 0px;
        opacity: 0.9;
        border: 2px solid #99e1d0;
        background-color: rgba(234, 253, 240, 0.9);
        border-radius: 0 10px 10px 0;
    }

    #input {
        margin: 5px;
        border: none;
        color: #000000;
        background-color: #fdba00;
    }

    #inner-box {
        margin: 5px;
        border: none;
        background-color: #eafdf0;
    }

    #outer-box {
        margin: 5px;
        border: none;
        background-color: #eafdf0;
    }

    #text {
        margin: 5px;
        border: none;
        color: #000000;
    }

    #entry:selected {
        background-color: #7897e8;
        border-radius: 6px;
    }

    list {
        background-color: #7897e8;
        border-radius: 6px;
    }
  '';

  themedWofi = pkgs.symlinkJoin {
    name = "wofi-custom";
    paths = [ pkgs.wofi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wofi --add-flags "--style ${wofiStyle}"
    '';
  };

  # Theme for the status dropdowns, deliberately separate from the
  # launcher above: the launcher is light and high-contrast because it is
  # something you type into, whereas a panel is read-only and should sit
  # quietly under a dark bar. Reusing the launcher sheet would also mean
  # a panel and a launcher could not be open at the same time without
  # looking like the same window.
  panelStyle = pkgs.writeText "wofi-panel-style.css" ''
    window {
        margin: 0px;
        padding: 0px;
        opacity: 0.97;
        border: 2px solid #${colors.blue};
        border-radius: 0 0 10px 10px;
        background-color: #${colors.bg};
    }

    #outer-box {
        margin: 0px;
        padding: 0px;
        border: none;
        background-color: #${colors.bg};
    }

    #inner-box {
        margin: 0px;
        padding: 6px;
        border: none;
        background-color: #${colors.bg};
    }

    #text {
        margin: 0px;
        padding: 0px;
        border: none;
        color: #${colors.fg};
    }

    list {
        background-color: #${colors.bg};
        border: none;
    }

    #entry:selected, listchild:selected {
        background-color: #${colors.brightBg};
        border-radius: 4px;
    }
  '';

  # wofi preloaded with the panel stylesheet, kept apart from the
  # launcher wrapper so the two themes cannot collide.
  panelWofi = pkgs.symlinkJoin {
    name = "wofi-panel";
    paths = [ pkgs.wofi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wofi --add-flags "--style ${panelStyle}"
    '';
  };

  # Dock theme, previously only reachable through a commented-out
  # `ln -sf` in sway.nix. It is now baked into the wrapper.
  nwgDockStyle = pkgs.writeText "nwg-dock-style.css" ''
    window {
        background-color: rgba(234, 253, 240, 0.9);
        border: 2px solid #99e1d0;
        border-radius: 10px;
    }
    #box {
        padding: 4px;
    }
    image {
        padding: 4px;
        margin: 0px 4px;
    }
    image:hover {
        background-color: #7897e8;
        border-radius: 6px;
    }
  '';

  themedNwgDock = pkgs.symlinkJoin {
    name = "nwg-dock-custom";
    paths = [ pkgs.nwg-dock ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/nwg-dock --add-flags "-s ${nwgDockStyle}"
    '';
  };

  # Wallpaper rotation. awww is a layer-shell client, so it works the same
  # under sway and Hyprland and the one script serves both sessions.
  installScript =
    name: path:
    pkgs.runCommand name { } ''
      install -Dm755 ${path} $out/bin/${name}
    '';

  wallpaperChanger = installScript "wallpaper-changer" ./wallpaper-changer.pl;
in
{
  options.wayland = {
    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "Habamax palette shared by the console, bars and window borders.";
    };

    statusBar = lib.mkOption {
      type = lib.types.package;
      description = ''
        Status line shared by sway's bar and Hyprland's waybar. Emits
        pango markup, so both bars colour the same segments.
      '';
    };

    wofi = lib.mkOption {
      type = lib.types.package;
      description = "wofi, preloaded with the shared launcher stylesheet.";
    };

    nwgDock = lib.mkOption {
      type = lib.types.package;
      description = "nwg-dock, preloaded with the shared dock stylesheet.";
    };

    wallpaperChanger = lib.mkOption {
      type = lib.types.package;
      description = ''
        Rotates ~/Pictures/Wallpaper through awww. Shared by both
        compositors so they show the same wallpaper at the same time.
      '';
    };

    panel = lib.mkOption {
      type = lib.types.package;
      description = ''
        Dropdown shown when a bar segment is clicked, rendered with the
        panel wofi theme. Takes --section net|disk|cpu|mem|time, so each
        segment can have its own content instead of every one of them
        opening the same program.
      '';
    };

    statusRuntimeDeps = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Programs status-line.sh needs on PATH. A systemd unit running
        the status script must add these to its `path`, because the
        default unit PATH does not include them.
      '';
    };
  };

  config = {
    wayland = {
      inherit colors;
      statusBar = statusScript;
      panel = panelScript;
      wofi = themedWofi;
      nwgDock = themedNwgDock;
      wallpaperChanger = wallpaperChanger;
      statusRuntimeDeps = statusRuntimeDeps;
    };

    # Both compositors reach these through the session PATH.
    environment.systemPackages = [
      config.wayland.statusBar
      config.wayland.panel
      config.wayland.wofi
      config.wayland.wallpaperChanger
    ];
  };
}
