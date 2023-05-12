{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;

  boot.kernelPackages = pkgs.linuxPackages_6_2;
  boot.kernelModules = [ "kvm-amd" "iwlwifi" ];
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
  # FIXME
  # still feels dirty
  # best guide: https://mcwhirter.com.au/craige/blog/2019/Setting_Up_Wireless_Networking_with_NixOS/
  networking.wireless.networks = {
    Sulaco = {
      pskRaw =
        "68a22d0495e941f027cdafc16a98945ad02f5a7ad13da2f8dfb8ab23669fe7d9"; # (password will be written to /nix/store!)
    };
  };
  networking.nat.enable = false;
  # networking.nat.internalInterfaces = [ ];
  # networking.nat.externalInterface = "enp9s0";

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
  networking.interfaces.enp9s0.useDHCP = false;
  networking.interfaces.wlp4s0.useDHCP = true;
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
    #autoOptimiseStore = true;
    settings.auto-optimise-store = true;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  environment.systemPackages = with pkgs; [
    awscli2
    bluez-tools
    vscode
    curl
    cwm
    doas
    direnv
    ed
    vim
    vlc
    wget
    minikube
    neofetch
    nixfmt
    firefox
    fd
    google-chrome
    microsoft-edge
    git
    go
    qemu
    oneko
    ripgrep
    scrot
    screen
    spotify
    polybar
    xscreensaver
    libbluray
    libaacs
    synergy
    jq
    mpv
    feh
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

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.X11Forwarding = false;
  # keybase service
  services.keybase.enable = false;

  # Enable CUPS to print documents.
  services.printing.enable = true;
  # If true and not using printer often
  # the jounrnal will get polluted with messages...
  services.avahi.enable = false;
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

  sound.enable = true;
  hardware.pulseaudio.enable = true;

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

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    layout = "us";
    autorun = false;
    exportConfiguration = true;
    displayManager.startx.enable = true;
    windowManager.cwm.enable = true;
    windowManager.i3.enable = false;
    videoDrivers = [ "nvidia" ];
  };
  # Enable the GNOME Desktop Environment.
  services.xserver.desktopManager.gnome.enable = true;
  # services.xserver.xkbOptions = "eurosign:e";

  virtualisation.docker.enable = true;
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
