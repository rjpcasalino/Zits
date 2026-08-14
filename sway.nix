{ config, pkgs, ... }:

let
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

  customWofi = pkgs.symlinkJoin {
    name = "wofi-custom";
    paths = [ pkgs.wofi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wofi --add-flags "--style ${wofiStyle}"
    '';
  };
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
      waybar
      wl-clipboard
      grim
      slurp
      customWofi
      mako
      qt5.qtwayland
      qt6.qtwayland
      gammastep # Redshift alternative for Wayland
      mpvpaper # Interactive 4K video/GIF wallpaper for Wayland
      awww # Animated GIF wallpaper engine with smooth transitions (formerly swww)
    ];
  };

  # Direct system /etc/sway/config to use /etc/nixos/sway.conf
  environment.etc."sway/config".source = ./sway.conf;
  environment.etc."sway/sway-window-switcher.py" = {
    source = ./sway-window-switcher.py;
    mode = "0755";
  };
  environment.etc."sway/wallpaper-changer.pl" = {
    source = ./wallpaper-changer.pl;
    mode = "0755";
  };
  environment.etc."sway/status.sh" = {
    source = ./sway-status-bar.sh;
    mode = "0755";
  };

  # Direct system /etc/xdg/foot/foot.ini to use /etc/nixos/foot.ini
  environment.etc."xdg/foot/foot.ini".source = ./foot.ini;

  system.activationScripts.setupFootConfig = ''
    mkdir -p /home/rjpc/.config/foot
    ln -sf /etc/nixos/foot.ini /home/rjpc/.config/foot/foot.ini
    chown -R rjpc:users /home/rjpc/.config/foot
  '';

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1"; # Wayland support for Electron/Chromium apps
  };
}
