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
  # still feels dirty
  # best guide: https://mcwhirter.com.au/craige/blog/2019/Setting_Up_Wireless_Networking_with_NixOS/
  networking.wireless.networks = {
    Sulaco = {
      pskRaw = "68a22d0495e941f027cdafc16a98945ad02f5a7ad13da2f8dfb8ab23669fe7d9"; # (password will be written to /nix/store!)
    };
  };
  #environment.etc.hosts.mode = "0600";
  networking.networkmanager.enable = false;
  networking.extraHosts =
  ''
    172.17.0.1 host.docker.internal
  '';

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp9s0.useDHCP = true;
  networking.interfaces.wlp4s0.useDHCP = true;
  networking.nameservers = [ "192.168.0.19" ];
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
    awscli2
    bluez-tools
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
    firefox
    fd
    google-chrome
    git
    go
    qemu
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
    # keybase
    kbfs
    keybase
    keybase-gui
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

  # Keybase # FIXME? Not working?
  services.keybase.enable = true;

  # Android
  programs.adb.enable = true;

  programs.bash.promptInit =  ''

      PS1="\n\[\033[01;32m\]\u $\[\033[00m\]\[\033[01;36m\] \w >\[\033[00m\]\n"

'';

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip ];

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
        Experimental = "true";
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
    windowManager.i3.enable = true;
    videoDrivers = [ "nvidia" ];
  };
  # services.xserver.xkbOptions = "eurosign:e";

  virtualisation.docker.enable = true;
  virtualisation.podman.enable = false;
  virtualisation.libvirtd.enable = false;
  virtualisation.virtualbox.host.enable = false;
  virtualisation.lxd.enable = false;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [ "cdrom" "wheel" "audio" "docker" "sound" "lxd" "adbusers" ];
    shell = "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}";
  };

  # this should be used for work stuff moving forward
  users.users.truman= {
    isNormalUser = true;
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
  };

  system.stateVersion = "22.11";
}
