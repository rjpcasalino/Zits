{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
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

  # SOPS
  sops.defaultSopsFile = "/home/rjpc/secrets/zits.yaml";
  sops.validateSopsFiles = false;
  sops.secrets."wireless.env" = { };

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

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp6s0.useDHCP = true;
  networking.interfaces.wlp5s0.useDHCP = true;
  networking.nameservers = [ "192.168.0.19" ];
  networking.enableIPv6 = true;

  # Open ports in the firewall.
  # only synergy thus far...
  networking.firewall.allowedTCPPorts = [ 24800 51413 ];
  # networking.firewall.allowedUDPPorts = [ 53 ];
  # Or disable the firewall altogether.
  networking.firewall.enable = true;
  # services.resolved.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # General Font Stuff #
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

  # TIME ZONE
  time.timeZone = "America/Los_Angeles";

  # nixpkgs
  # TODO: clean up?
  # FIXME: seems config.nix conflicts with this
  nixpkgs.config.allowUnfree = true;
  # for BLE stuff? broken? see above
  # nixpkgs.config.segger-jlink.acceptLicense = true;

  ## MPV OVERLAY ##
  ## if you want vlc back just
  ## use same overlay
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

  nix = {
    package = pkgs.nixUnstable;
    settings.auto-optimise-store = true;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

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
    nixpkgs-fmt
    neofetch
    nil
    mpv-unwrapped
    microsoft-edge
    minikube
    oneko
    polybar
    pamixer
    qemu
    ripgrep
    rnix-lsp
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

  # Android
  programs.adb.enable = true;
  # Steam
  programs.steam.enable = true;
  programs.bash.promptInit = ''
    PS1="\n\[\033[01;32m\]\u $\[\033[00m\]\[\033[01;36m\] \w >\[\033[00m\]\n"
  '';
  # FIXME: remove?
  services.kmscon.enable = false;
  # General Purpose Mouse daemon, which enables mouse support in virtual consoles
  services.gpm.enable = true;
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
  # keybase service
  services.keybase.enable = false;
  # Enable CUPS to print documents.
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

  hardware.pulseaudio.enable = false;
  # TODO: move this
  # also, I removed sound.enable
  security.rtkit.enable = true;
  security.doas.enable = true;
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    wireplumber.enable = true;
    pulse.enable = true;
  };

  # TODO
  # look into LE settings
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

  # related to bluetooth HSP/HFP mode
  # see: https://nixos.wiki/wiki/Bluetooth#No_audio_when_using_headset_in_HSP.2FHFP_mode
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  # Enable the X11 windowing system.
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
  xdg.portal.enable = false;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
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

  # this should be used for work stuff moving forward
  users.users.truman = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" "docker" "sound" ];
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
  };

  system.stateVersion = "22.11";
}
