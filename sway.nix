{ config, pkgs, ... }:

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
      wofi
      wl-clipboard
      grim
      slurp
      mako
      qt5.qtwayland
      qt6.qtwayland
      gammastep   # Redshift alternative for Wayland
      mpvpaper    # Interactive 4K video/GIF wallpaper for Wayland
      awww        # Animated GIF wallpaper engine with smooth transitions (formerly swww)
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
