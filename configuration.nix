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

  networking.hostName = "zits";
  networking.wireless.enable =
    true; # Enables wireless support via wpa_supplicant.
  networking.wireless.userControlled.enable = true;
  networking.wireless.iwd.enable = false;
  networking.wireless.scanOnLowSignal = false;
  # use wpa_passphrase or whatnot
  networking.wireless.networks = {
    Sulaco = {
      pskRaw =
        "68a22d0495e941f027cdafc16a98945ad02f5a7ad13da2f8dfb8ab23669fe7d9"; # (password will be written to /nix/store!)
    };
  };
  networking.nat.enable = false;
  # networking.nat.internalInterfaces = [ ];
  # networking.nat.externalInterface = "enp5s0";

  # see: https://discourse.nixos.org/t/a-fast-way-for-modifying-etc-hosts-using-networking-extrahosts/4190
  environment.etc.hosts.mode = "0644";
  networking.networkmanager.enable = false;
  networking.extraHosts = ''
    172.17.0.1 host.docker.internal
  '';

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp6s0.useDHCP = false;
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
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # nixpkgs
  # TODO: clean up?
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (self: super: {
      vlc = super.vlc.override {
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
    jq
    libbluray
    libaacs
    nixpkgs-fmt
    neofetch
    nil
    mpv
    microsoft-edge
    minikube
    oneko
    polybar
    qemu
    ripgrep
    rnix-lsp
    redshift
    scrot
    screen
    spotify
    synergy
    vim
    vlc
    vscode
    wget
    xscreensaver
    xorg.xmodmap
    xorg.xev
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  #   pinentryFlavor = "gnome3";
  # };

  # Android stuff
  programs.adb.enable = true;
  # steam
  programs.steam.enable = true;
  programs.bash.promptInit = ''

    PS1="\n\[\033[01;32m\]\u $\[\033[00m\]\[\033[01;36m\] \w >\[\033[00m\]\n"

  '';
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
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    wireplumber.enable = true;
    pulse.enable = true;
  };

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
    windowManager.cwm.enable = true;
    windowManager.i3.enable = false;
    # this will pick amdgpu by default
    videoDrivers = [ "modesetting" ];
  };

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
