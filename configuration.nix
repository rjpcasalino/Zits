{ config, pkgs, inputs, lib, ... }:


{
  imports = [
    ./hardware-configuration.nix
    ./editor.nix
    ./shell.nix
  ];

  ## boot ##
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "kvm-amd" "k10temp" "sg" "nct6775" "8852bu" ];
  boot.extraModulePackages = [ ];
  boot.extraModprobeConfig = ''
  '';
  boot.kernelParams = [ ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv6l-linux" ];
  boot.tmp.cleanOnBoot = true;
  boot.loader.systemd-boot.consoleMode = "max";
  boot.blacklistedKernelModules = [ "ucsi_ccg" ];
  # #

  # documentation #
  documentation = {
    enable = true;
    doc.enable = true;
    man = {
      enable = true;
      cache.enable = false; # https://discourse.nixos.org/t/slow-build-at-building-man-cache/52365/14
    };
    info.enable = true;
  };
  # #

  # nixpkgs and nix #
  nixpkgs = {
    config = {
      allowUnfree = true;
      enableParallelBuildingByDefault = false;
      rocmSupport = true;
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
    settings.auto-optimise-store = true;
    # auto-allocate-uids started throwing warnings with recent update to Uakari
    extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids
    '';
    channel.enable = false;
    registry.nixpkgs.flake = inputs.nixpkgs;
    settings.show-trace = true;
  };
  # #

  # systemd services #
  systemd.services = {
    backup-diary-service = {
      path = [
        pkgs.openssh
      ];
      script = ''
        scp /home/rjpc/diary.merged rjpc@nemo.home.arpa:~
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
    # HABAMAX-ALIGNED PALETTE
    colors = [
      "1c1c1c" # Color 0:  Black          (habamax color00 - dark bg)
      "af5f5f" # Color 1:  Red            (habamax color01 - muted brick red)
      "5faf5f" # Color 2:  Green          (habamax color02 - muted mid green)
      "af875f" # Color 3:  Yellow         (habamax color03 - warm tan/brown)
      "5f87af" # Color 4:  Blue           (habamax color04 - steel blue)
      "af87af" # Color 5:  Magenta        (habamax color05 - dusty mauve)
      "5f8787" # Color 6:  Cyan           (habamax color06 - muted teal)
      "9e9e9e" # Color 7:  White          (habamax color07 - medium grey)
      "767676" # Color 8:  Bright Black   (habamax color08 - visible dark grey)
      "d75f87" # Color 9:  Bright Red     (habamax color09 - pink-red)
      "87d787" # Color 10: Bright Green   (habamax color10 - soft lime green)
      "d7af87" # Color 11: Bright Yellow  (habamax color11 - warm sand)
      "5fafd7" # Color 12: Bright Blue    (habamax color12 - sky blue)
      "d787d7" # Color 13: Bright Magenta (habamax color13 - soft violet)
      "87afaf" # Color 14: Bright Cyan    (habamax color14 - pale cyan)
      "c7c7c7" # Color 15: Bright White   (habamax color15 - light grey white)
    ];
  };
  # Services #
  services.dictd.enable = false;
  services.gnome.gnome-keyring.enable = true;
  # seahorse is a UI for keyring
  programs.seahorse.enable = true;
  # git
  programs.git.enable = true;
  # General Purpose Mouse daemon—enables mouse support in virtual consoles
  services.gpm.enable = true;
  services.kmscon.enable = false;
  # ollama
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    rocmOverrideGfx = "11.0.1";
    environmentVariables = {
      OLLAMA_DEBUG = "1";
      OLLAMA_HOST = "0.0.0.0";
      HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      HCC_AMDGPU_TARGET = "gfx1100";
    };
  };
  # #

  # Internationalisation properties #
  i18n.defaultLocale = "en_US.UTF-8";
  # #

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.allowSFTP = true;
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
  services.clamav.daemon.enable = false;
  services.clamav.updater.enable = false;
  # #

  # Fonts #
  fonts.enableDefaultPackages = true;
  fonts.enableGhostscriptFonts = true;
  # #

  # Networking #
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.interfaces.enp13s0f2u1u1.useDHCP = true;
  networking.interfaces.wlan0.useDHCP = true;
  networking.hostName = "zits";
  networking.enableIPv6 = true;
  networking.wireless = {
    iwd.enable = true;
    iwd.settings = {
      Rank.BandModifier6GHz = 2.0;
      Rank.BandModifier5GHz = 1.5;
      Rank.BandModifier2_4GHz = 1.0;
    };
    enable = false;
    secretsFile = config.sops.secrets."wireless.env".path;
    userControlled.enable = true;
    scanOnLowSignal = false;
    # we don't need to blacklist these bssid anymore
    # but good example of how to do so.
    # FIXME:
    # pskRaw no longer works for WPA3?
    networks = {
      "ext:ssid" = {
        pskRaw = "ext:psk";
        #keyMgmt = "EXTERNAL_AUTH";
        extraConfig = ''
        '';
      };
    };
  };
  # see: https://discourse.nixos.org/t/a-fast-way-for-modifying-etc-hosts-using-networking-extrahosts/4190
  # note: the hosts mode is to allow vpn split to work for mct (no longer needed but will del later - July 2024)
  # environment.etc.hosts.mode = "0644";

  # not sure this extraHosts stuff is working
  networking.extraHosts = ''
    172.17.0.1 host.docker.internal
    0.0.0.0 www.asusrouter.com
  '';

  # Firewall
  networking.firewall.enable = true;
  # synergy is 24800
  networking.firewall.allowedTCPPorts = [ ];
  # https://datatracker.ietf.org/doc/html/rfc6056
  # allows tftp
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 0;
      to = 65535;
    }
  ];
  # #

  services.flatpak.enable = true;
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
  services.printing.drivers = [ pkgs.hplip pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];
  # #

  # Audio and Sound #
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = false;
    wireplumber.enable = true;
    pulse.enable = true;
    extraConfig.pipewire = {
      "99-disable-bell" = {
        "context.properties" = {
          "module.x11.bell" = false;
        };
      };
    };
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
  hardware.graphics.enable = true;
  hardware.amdgpu.opencl.enable = true;
  hardware.graphics.extraPackages = [
    pkgs.rocmPackages.clr.icd
    pkgs.rocmPackages.hipblaslt
  ];
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    autorun = true;
    xkb.options = "compose:ralt";
    exportConfiguration = true;
    displayManager.startx.enable = false;
    displayManager.lightdm = {
      enable = false;
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
    desktopManager.xfce.enable = true;
    desktopManager.wallpaper.mode = "scale";
  };
  services.displayManager.gdm.enable = true;
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
    configPackages = [ pkgs.gnome-session ];
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  # #

  # Docker et al
  virtualisation.docker = {
    enable = true;
    logDriver = "journald";
    liveRestore = true;
    # package = pkgs.docker_27; # if you want a version other than latest?
    daemon.settings = {
      ipv6 = true;
      "fixed-cidr-v6" = "2001:db8:1::/64";
    };
  };
  virtualisation.docker.autoPrune = {
    enable = true;
    flags = [ "--all, --volumes" ];
  };
  virtualisation.podman.enable = false;
  virtualisation.libvirtd.enable = false;
  virtualisation.virtualbox.host.enable = false;
  # #

  # system and users #
  environment.pathsToLink = [ "/share/zsh" ];
  environment.wordlist.enable = true;
  environment.systemPackages = with pkgs; [
    age
    arandr
    #awscli2
    bluez-tools
    bc
    curl
    cmake
    deploy-rs
    direnv
    dust
    ed
    eslint
    fd
    feh
    ffmpeg-full
    fortune
    inputplug
    go
    gopls
    grpcui
    lact
    # libreoffice # FUCK
    # makemkv # FUCK
    neofetch
    nixpkgs-fmt
    nixpkgs-review
    pamixer
    pciutils
    # rpi-imager # fucking broken and no time to fix.
    ripgrep
    screen
    scrot
    slack
    unzip
    usbutils
    wget
    xdg-utils
    libXft
    xev
    xmodmap
    xscreensaver
    zathura
    zoom-us
    clamav
    firefox
    htop
    gnupg
    gnumake
    google-chrome
    gemini-cli
    libaacs
    libbluray
    mons
    mpv-unwrapped # see overlays
    nodejs
    nodePackages_latest.prettier
    nodePackages_latest.eslint # might be doing this twice (in home.nix too)
    overskride
    polybar
    p11-kit
    sops
    (vscode-with-extensions.override {
      vscodeExtensions = with vscode-extensions; [
        bbenoist.nix
        dracula-theme.theme-dracula
        eamodio.gitlens
        enkia.tokyo-night
        golang.go
        mechatroner.rainbow-csv
        ms-azuretools.vscode-docker
        ms-toolsai.jupyter
        ms-python.python
        ms-vscode.makefile-tools
        naumovs.color-highlight
      ];
    })
    # wine
    #(pkgs.lutris.override {
    #  extraPkgs = pkgs: [
    #    pkgs.wineWow64Packages.stagingFull
    #    pkgs.winetricks
    #  ];
    # })
  ];
  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [
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
