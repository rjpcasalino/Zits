{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];
  
  ## boot ##
  # systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "kvm-amd" "iwlwifi" "k10temp" ];
  # this is for wifi and bluetooth antenna
  boot.extraModulePackages = [ config.boot.kernelPackages.rtl88x2bu ];
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=N
    options iwldvm force_cam=Y
  '';
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv6l-linux" ];
  # #

  # SOPS
  sops.defaultSopsFile = "/home/rjpc/secrets/zits.yaml";
  sops.validateSopsFiles = false;
  sops.secrets."wireless.env" = { };
  # #

  # Security
  security.rtkit.enable = true;
  security.doas.enable = true;
  # #

  # Networking #
  networking.wireless.environmentFile = config.sops.secrets."wireless.env".path;
  networking.hostName = "zits";
  networking.wireless.enable =
    true; # Enables wireless support via wpa_supplicant.
  # networking.wireless.enable and networking.wireless.iwd.enable are mutually exclusive
  networking.wireless.userControlled.enable = true;
  networking.wireless.scanOnLowSignal = false;
  # use wpa_passphrase
  # we don't need to blacklist these bssid anymore
  # but good example of how to do so.
  networking.wireless.networks = {
    "@ssid@" = {
      pskRaw = "@pskRaw@";
      extraConfig = ''
        bssid_blacklist=80:cc:9c:f1:b8:7b 80:cc:9c:f1:82:03
      '';
    };
  };
  networking.nat.enable = false;
  # networking.nat.internalInterfaces = [ ];
  # networking.nat.externalInterface = "enp5s0";
  # see: https://discourse.nixos.org/t/a-fast-way-for-modifying-etc-hosts-using-networking-extrahosts/4190
  # note: the hosts mode is to allow vpn split to work for mct
  environment.etc.hosts.mode = "0644";
  # not sure this extraHosts stuff is working
  networking.networkmanager.enable = false;
  networking.extraHosts = ''
    172.17.0.1 host.docker.internal
  '';
  # The global useDHCP flag is deprecated
  networking.useDHCP = false;
  networking.interfaces.enp6s0.useDHCP = true;
  networking.interfaces.wlp5s0.useDHCP = true;
  networking.nameservers = [ "192.168.0.19" ];
  networking.enableIPv6 = true;
  services.resolved.enable = true;

  # Firewall
  networking.firewall.enable = true;
  # synergy is 51413. Not sure about 24800
  networking.firewall.allowedTCPPorts = [ 24800 51413 ];
  # networking.firewall.allowedUDPPorts = [ 53 ];
  # #

  # Internationalisation properties #
  i18n.defaultLocale = "en_US.UTF-8";
  # #

  # Font Stuff #
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v16n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
  };
  fonts.fonts = with pkgs; [
    nerdfonts
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
  ];
  # #

  # TIME ZONE
  time.timeZone = "America/Los_Angeles";
  # #

  # nix and nixpkgs #
  # FIXME: seems config.nix conflicts with this
  nixpkgs.config.allowUnfree = true;
  # for BLE stuff? broken?
  # nixpkgs.config.segger-jlink.acceptLicense = true;
  nix = {
    package = pkgs.nixUnstable;
    settings.auto-optimise-store = true;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
  # #

  # Misc programs #
  # Android
  programs.adb.enable = true;
  # Steam
  programs.steam.enable = true;
  # #

  # bash #
  programs.bash.promptInit = ''
    PS1="\n\[\033[01;32m\]\u $\[\033[00m\]\[\033[01;36m\] \w >\[\033[00m\]\n"
  '';
  # #

  # Linux console #
  services.kmscon.enable = false;
  # General Purpose Mouse daemon, which enables mouse support in virtual consoles
  services.gpm.enable = true;
  # #

  # FIXME
  # this wasn't working so do it
  # hard way via xinitrc
  services.redshift.enable = false;
  # for redshift
  location.latitude = 47.36;
  location.longitude = -122.19;
  location.provider = "manual";

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.X11Forwarding = false;
  # #

  # keybase service
  services.keybase.enable = false;
  
  # CUPS and SANE #
  services.printing.enable = true;
  # If true and not using printer often
  # the jounrnal will get polluted with messages...
  # also needed for geoclue and redshift?
  services.avahi.enable = true;
  # Enable SANE for scanning
  hardware.sane.enable = true;
  services.avahi.nssmdns = true;
  # Needed since this is an HP scanner 
  # hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];
  # use below as above does not seem to scan but sees scanner
  # see: https://github.com/alexpevzner/sane-airscan
  hardware.sane.extraBackends = [ pkgs.sane-airscan ];
  # for a WiFi printer
  services.avahi.openFirewall = true;
  services.printing.drivers = [ pkgs.hplip ];
  # #

  # Audio and Sound #
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    wireplumber.enable = true;
    pulse.enable = true;
  };
  # #
  
  # related to bluetooth HSP/HFP mode
  # see: https://nixos.wiki/wiki/Bluetooth#No_audio_when_using_headset_in_HSP.2FHFP_mode
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Name = "Zits";
        ControllerMode = "dual";
        FastConnectable = "true";
        Experimental = "true";
      };
      Policy = { AutoEnable = "true"; };
      LE = { EnableAdvMonInterleaveScan = "true"; };
    };
  };

  # X11 et al #
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  services.xserver = {
    enable = true;
    layout = "us";
    autorun = false;
    exportConfiguration = true;
    displayManager.startx.enable = true;
    displayManager.setupCommands = ''
      ${pkgs.xorg.xrandr}/bin/xrandr --output "DP-1" --primary --rotate normal --output "HDMI-1" --rotate normal --left-of "DP-1"
    '';
    windowManager.cwm.enable = true;
    windowManager.i3.enable = false;
    # this will pick amdgpu by default
    videoDrivers = [ "modesetting" ];
    libinput = {
      enable = true;
      mouse = {
        middleEmulation = true;
        tapping = false;
        tappingButtonMap = "lmr";
      };
    };
  };
  # #

  # xdg; TODO: learn more
  xdg.portal.enable = false;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  # #

  # Docker et al
  virtualisation.docker = {
    enable = true;
    logDriver = "journald";
    liveRestore = true;
    package = pkgs.docker;
  };
  virtualisation.docker.autoPrune = {
    enable = true;
    flags = [ "--all, --volumes" ];
  };
  virtualisation.podman.enable = false;
  virtualisation.libvirtd.enable = false;
  virtualisation.virtualbox.host.enable = false;
  virtualisation.lxd.enable = false;
  # #

  ## overlays ##
  nixpkgs.overlays = [
    (self: super: {
      mpv-unwrapped = super.mpv-unwrapped.override {
        libbluray = super.libbluray.override {
          withAACS = true;
          withBDplus = true;
        };
      };
    })
  ];
  # #

  # system and users # 
  environment.systemPackages = with pkgs; [
    arandr
    awscli2
    bluez-tools
    curl
    cwm
    direnv
    du-dust
    docker-compose
    ed
    firefox
    fd
    feh
    ffmpeg-full
    git
    go
    gopls
    google-chrome
    gnupg
    jq
    libbluray
    libaacs
    mpv-unwrapped # see overlays
    microsoft-edge
    minikube
    nixpkgs-fmt
    neofetch
    oneko
    polybar
    pamixer
    qemu
    ripgrep
    rnix-lsp # nix lang server
    redshift
    rpi-imager
    scrot
    screen
    spotify
    slack
    synergy
    sops
    vim
    vscode
    wget
    xdg-utils
    xscreensaver
    xorg.xmodmap
    xorg.xev
    zoom-us
  ];
  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [
      "cdrom"
      "dialout"
      "wheel"
      "audio"
      "docker"
      "sound"
      "lxd"
      "adbusers"
      "scanner"
      "lp"
    ];
    shell = "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}";
  };
  users.users.truman = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" "docker" "sound" ];
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
  };
  system.stateVersion = "22.11";
}
