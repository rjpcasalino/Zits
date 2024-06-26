{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  ## boot ##
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = false;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "kvm-amd" "iwlwifi" "k10temp" "sg" "amdgpu" "8852bu" ];
  # is there a better way to ref 8852bu
  boot.extraModulePackages = [ pkgs.linuxPackages_latest.rtl8852bu ];
  boot.extraModprobeConfig = ''
    options 8852bu rtw_switch_usb_mode=0 rtw_he_enable=2 rtw_vht_enable=2 rtw_dfs_region_domain=1
  '';
  boot.kernelParams = [ ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv6l-linux" ];
  boot.tmp.cleanOnBoot = true;
  boot.loader.systemd-boot.consoleMode = "max";
  # #

  # documentation #
  documentation = {
    enable = true;
    doc.enable = true;
    man = {
      enable = true;
      generateCaches = false;
    };
    info.enable = true;
  };
  # #

  # nixpkgs and nix #
  nixpkgs = {
    config = {
      allowUnfree = true;
      enableParallelBuildingByDefault = false;
    };
  };
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
  # FIXME: this nixPath nonsense...
  # specialArgs = { inherit inputs; }—dumb
  # registry.nixpkgs.flake = inputs.nixpkgs—ugh
  nix = {
    settings.trusted-users = [ "root" "rjpc" ];
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    package = pkgs.nixVersions.latest;
    settings.auto-optimise-store = true;
    # auto-allocate-uids started throwing warnings with recent update to Uakari
    extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids configurable-impure-env
    '';
    channel.enable = true;
    registry.nixpkgs.flake = inputs.nixpkgs;
  };
  # #

  # systemd services #
  systemd.services = {
    backup-diary-service = {
      path = [
        pkgs.openssh
      ];
      script = ''
        cp /home/rjpc/EXSSD/diary.merged ~ \
        && scp /home/rjpc/EXSSD/diary.merged rjpc@nemo.home.arpa:~
      ''
      ;
      serviceConfig = {
        User = config.users.users.rjpc.name;
      };
      startAt = "hourly";
    };
  };
  # #

  # TIME ZONE
  time.timeZone = "America/Los_Angeles";
  # #

  # Linux console #
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v16n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
    colors = [
      # TODO:
      # map these colors with comments
      "002b36"
      "dc322f"
      "859900"
      "b58900"
      "268bd2"
      "d33682"
      "2aa198"
      "eee8d5"
      "002b36"
      "cb4b16"
      "586e75"
      "657b83"
      "839496"
      "6c71c4"
      "93a1a1"
      "fdf6e3"
    ];
  };
  # Services #
  services.gnome.gnome-keyring.enable = true;
  # seahorse is a UI for keyring
  programs.seahorse.enable = true;
  # General Purpose Mouse daemon—enables mouse support in virtual consoles
  services.gpm.enable = true;
  services.kmscon.enable = false;
  services.ollama.enable = true;
  services.ollama.acceleration = "rocm";
  # #

  # Internationalisation properties #
  i18n.defaultLocale = "en_US.UTF-8";
  # #

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.X11Forwarding = false;
  # #

  # SOPS
  sops.defaultSopsFile = "/home/rjpc/secrets/zits.yaml";
  sops.validateSopsFiles = false;
  sops.secrets."wireless.env" = { };
  # #

  # Security
  security.rtkit.enable = true;
  security.doas = {
    enable = false;
    wheelNeedsPassword = false;
  };
  security.sudo.wheelNeedsPassword = false;
  # #

  # Anti-virus #
  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;
  # #

  # Fonts #
  fonts.enableDefaultPackages = true;
  fonts.enableGhostscriptFonts = true;
  fonts.packages = with pkgs; [
    emojione
    nerdfonts
    noto-fonts
    openmoji-black
    openmoji-color
  ];
  # #

  # Networking #
  networking.hostName = "zits";
  networking.enableIPv6 = true;
  networking.wireless = {
    iwd.enable = true;
    enable = false; # iwd enabled
    environmentFile = config.sops.secrets."wireless.env".path;
    userControlled.enable = true;
    scanOnLowSignal = false;
    # we don't need to blacklist these bssid anymore
    # but good example of how to do so.
    # FIXME:
    # pksRaw no longer works for WPA3?
    networks = {
      "@ssid@" = {
        psk = "@psk@";
        extraConfig = ''
          bssid_blacklist=80:cc:9c:f1:b8:7b 80:cc:9c:f1:82:03
        '';
      };
    };
  };
  # see: https://discourse.nixos.org/t/a-fast-way-for-modifying-etc-hosts-using-networking-extrahosts/4190
  # note: the hosts mode is to allow vpn split to work for mct
  environment.etc.hosts.mode = "0644";
  # not sure this extraHosts stuff is working
  networking.extraHosts = ''
    172.17.0.1 host.docker.internal
  '';
  networking.interfaces.enp10s0.useDHCP = true;
  # networking.interfaces.wlp6s0.useDHCP = true; #
  # iwd does dhcp stuff
  # iwd renames interface to wlan0 #
  # asus AX55 nano might be wlan0 one day and wlan1 the next
  networking.interfaces.wlan1.useDHCP = true; # iwd does this
  # networking.nameservers = [ ];
  services.resolved.enable = false;
  services.resolved.fallbackDns = [ "8.8.8.8" "2001:4860:4860::8844" ];

  # Firewall
  networking.firewall.enable = true;
  # synergy is 24800
  networking.firewall.allowedTCPPorts = [ 24800 ];
  # #

  # Misc programs #
  programs.adb.enable = false;
  programs.steam.enable = true;
  services.udev.extraRules = ''
    # PS5 DualSense controller over USB hidraw
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"

    # PS5 DualSense controller over bluetooth hidraw
    KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
  '';
  # #

  services.redshift.enable = true;
  location.latitude = 47.608013;
  location.longitude = -122.335167;

  # CUPS and SANE #
  services.printing.enable = true;
  # If true and not using printer often
  # the jounrnal will get polluted with messages
  # Also needed for geoclue and redshift?
  services.avahi.enable = true;
  # Enable SANE for scanning
  hardware.sane.enable = true;
  services.avahi.nssmdns4 = true;
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
      # 1 is enabled and is enabled by default
      LE = { EnableAdvMonInterleaveScan = "1"; };
    };
  };

  # X11 et al #
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    autorun = true;
    xkb.options = "compose:ralt";
    exportConfiguration = true;
    displayManager.startx.enable = false;
    displayManager.lightdm = {
      enable = true;
      #background = /. + "/home/rjpc/Pictures/nix-wallpaper-moonscape.png";
      greeters.gtk.indicators = [
        "~host"
        "~spacer"
        "~clock"
        "~spacer"
        "~session"
        "~power"
      ];
      greeters.gtk.clock-format = "%A %F %I:%M%p";
    };
    windowManager.cwm.enable = true;
    desktopManager.wallpaper.mode = "center";
  };
  services.libinput = {
    enable = true;
    mouse = {
      middleEmulation = false;
      tapping = false;
      tappingButtonMap = "lmr";
    };
  };
  # #

  # TODO:
  # learn more about xdg—still confusing to me
  xdg.menus.enable = true;
  xdg.portal = {
    enable = true;
    configPackages = [ pkgs.gnome.gnome-session ];
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  # #

  # Docker et al
  virtualisation.docker = {
    enable = true;
    logDriver = "journald";
    liveRestore = true;
    package = pkgs.docker_25;
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

  # system and users #
  environment.pathsToLink = [ "/share/zsh" ];
  # TODO:
  # browsers should be set in home manager
  environment.systemPackages = with pkgs; [
    bluez-tools
    clamav
    firefox
    # replace with age?
    gnupg
    #
    gnumake
    google-chrome
    libaacs
    libbluray
    mpv-unwrapped # see overlays
    sops
    # TODO:
    # move to home manager but good
    # example of non-home manager setup
    (vscode-with-extensions.override {
      vscodeExtensions = with vscode-extensions; [
        bbenoist.nix
        dracula-theme.theme-dracula
        eamodio.gitlens
        enkia.tokyo-night
        golang.go
        mechatroner.rainbow-csv
        ms-azuretools.vscode-docker
        ms-vscode.makefile-tools
        naumovs.color-highlight
      ];
    })
  ];
  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [
      "adbusers"
      "audio"
      "cdrom"
      "dialout"
      "docker"
      "lp"
      "lxd"
      "scanner"
      "sound"
      "wheel"
    ];
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
  };
  system.stateVersion = "22.11";
}
