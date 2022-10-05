{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;
  boot.kernelModules = [ "kvm-amd" "iwlwifi" ];
  # this is for wifi and bluetooth antenna
  boot.extraModulePackages = with config.boot.kernelPackages; [ rtl88x2bu ];
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=N
    options iwldvm force_cam=Y
  '';

  networking.hostName = "zits";
  networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.
  networking.wireless.userControlled.enable = true;
  networking.wireless.iwd.enable = false;
  networking.wireless.scanOnLowSignal = false;
  # FIXME
  networking.wireless.networks = {
    Sulaco = {
      psk = "duffman2415"; # (password will be written to /nix/store!)
    };
  };
  networking.networkmanager.enable = false;

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp9s0.useDHCP = true;
  networking.interfaces.wlp4s0.useDHCP = true;
  networking.nameservers = [ "192.168.0.18" ];
  networking.enableIPv6 = false;

  # Open ports in the firewall.
  # only synergy thus far...
  networking.firewall.allowedTCPPorts = [ 24800 51413 ];
  # networking.firewall.allowedUDPPorts = [ 5000 ];
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
    # settings.substituters = [ "http://oystercatcher.home.arpa:5000" ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  environment.systemPackages = with pkgs; [
    bluez-tools
    curl
    cwm
    doas
    ed
    vim
    vlc
    wget
    neofetch
    firefox
    git
    go
    screen
    xscreensaver
    libbluray
    libaacs
    synergy
    vscode
    # keybase
    kbfs
    keybase
    keybase-gui
    minikube
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  #   pinentryFlavor = "gnome3";
  # };

  # steam
  # FIXME
  # some out error...ugh
  programs.steam.enable = false;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = false;

  # Keybase
  services.keybase.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Enable sound.
  sound.enable = true;

  # hardware
  hardware.pulseaudio.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Name = "Zits";
        ControllerMode = "dual";
        FastConnectable = "true";
      };
      Policy = {
        AutoEnable = "true";
      };
      LE = {
        EnableAdvMonInterleaveScan = "true";
      };
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
    videoDrivers = [ "nvidia" ];
  };
  # services.xserver.xkbOptions = "eurosign:e";

  virtualisation.docker.enable = true;
  virtualisation.podman.enable = false;
  virtualisation.libvirtd.enable = false;
  virtualisation.virtualbox.host.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [ "cdrom" "wheel" "audio" "docker" ];
    shell = "${pkgs.bashInteractive_5}${pkgs.bashInteractive_5.shellPath}";
  };

  system.stateVersion = "22.11";
}
