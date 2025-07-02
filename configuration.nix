{ config, pkgs, inputs, ... }:


{
  imports = [
    ./hardware-configuration.nix
    ./face_redux.nix
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
    colors = [
      # TODO:
      # map these colors with comments
      "002b36"
      "dc322f"
      "859900"
      "000000"
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
      "002b36"
      #002b36: Navy Blue
      #dc322f: Dark Red
      #859900): Forest Green
      #b58900: Olive Drab
      #268bd2: Sky Blue
      #d33682: Burnt Orange
      #2aa198: Light Steel Blue
      #eee8d5: Cream
      #002b36: Navy Blue
      #cb4b16: Brown
      #586e75: Mint Green
      #657b83: Forest Green (similar to #859900)
      #839496: Dark Teal
      #6c71c4: Medium Purple
      #93a1a1: Light Silver
      #fdf6e3: Beige

    ];
  };
  # Services #
  services.dictd.enable = false;
  services.gnome.gnome-keyring.enable = true;
  # seahorse is a UI for keyring
  programs.seahorse.enable = true;
  # General Purpose Mouse daemon—enables mouse support in virtual consoles
  services.gpm.enable = true;
  services.kmscon.enable = false;
  # ollama
  services.ollama = {
    enable = true;
    acceleration = "rocm";
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
  fonts.packages = with pkgs; [
    emojione
    nerd-fonts.hack
    nerd-fonts.noto
    nerd-fonts.symbols-only
    nerd-fonts.dejavu-sans-mono
    # nerdfonts # unstable moves this to the above
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
    iwd.settings = {
      Rank.BandModifier6GHz=2.0;
      Rank.BandModifier5GHz=1.5;
      Rank.BandModifier2_4GHz=1.0;
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
  # networking.interfaces.wlp6s0.useDHCP = true; #
  # iwd renames interface to wlan0 #
  networking.interfaces = {
    enp10s0.useDHCP = true;
    wlan0.useDHCP = true;
  };
  # networking.nameservers = [ ];

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

  # Programs misc
  services.flatpak.enable = true;
  programs.adb.enable = true;
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
  hardware.graphics.enable = true;
  # AMD GPU
  hardware.amdgpu = {
    amdvlk.enable = true;
    amdvlk.supportExperimental.enable = true;
    amdvlk.support32Bit.enable = true;
  };
  # #
  hardware.amdgpu.opencl.enable = true;
  hardware.graphics.extraPackages = [
   pkgs.rocmPackages.clr.icd
  ];
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    autorun = true;
    xkb.options = "compose:ralt";
    exportConfiguration = true;
    displayManager.startx.enable = false;
    displayManager.gdm.enable = true;
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
  virtualisation.lxd.enable = false;
  # #

  # system and users #
  environment.pathsToLink = [ "/share/zsh" ];
  environment.wordlist.enable = true;
  # TODO:
  # browsers should be set in home manager.
  environment.systemPackages = with pkgs; [
    bluez-tools
    clamav
    firefox
    htop
    # replace with age?
    gnupg
    #
    gnumake
    google-chrome
    libaacs
    libbluray
    mons
    mpv-unwrapped # see overlays
    nodejs
    nodePackages_latest.prettier
    nodePackages_latest.eslint # might be doing this twice (in home.nix too)
    overskride
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
        ms-toolsai.jupyter
        ms-python.python
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
    icon = /home/rjpc/.face ;
  };
  system.stateVersion = "22.11";
}
