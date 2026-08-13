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
    ];
  };

  # Direct system /etc/sway/config to use /etc/nixos/sway.conf
  environment.etc."sway/config".source = ./sway.conf;
  environment.etc."sway/sway-window-switcher.py" = {
    source = ./sway-window-switcher.py;
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
