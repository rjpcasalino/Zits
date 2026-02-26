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

    # THE CYBERDECK BASE PALETTE
    colors = [
      "1e2030" # Color 0:  Black
      "e82424" # Color 1:  Red
      "2dcc70" # Color 2:  Green
      "e5c07b" # Color 3:  Yellow (Amber)
      "26bbd9" # Color 4:  Blue
      "c678dd" # Color 5:  Magenta
      "56b6c2" # Color 6:  Cyan
      "828bb8" # Color 7:  White (Light Gray)
      "444a73" # Color 8:  Bright Black (Used for muted UI elements)
      "ff3333" # Color 9:  Bright Red (Errors)
      "33ff00" # Color 10: Bright Green (Phosphor success / user)
      "ffcc00" # Color 11: Bright Yellow (Git status warning)
      "0066ff" # Color 12: Bright Blue (Nix shell)
      "ff00ff" # Color 13: Bright Magenta (Git branch)
      "00ffff" # Color 14: Bright Cyan (Directory)
      "ffffff" # Color 15: Bright White
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
  systemd.network.wait-online.anyInterface = true;
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

  # Programs misc
  #programs.zsh = {
  #  enable = true;
  #  autosuggestions.enable = true;
  #  histSize = 10000;
  #  histFile = "$HOME/.zsh_history";
  #  setOptions = [
  #    "HIST_IGNORE_ALL_DUPS"
  #  ];
  #  shellAliases = {
  #    ".." = "cd ..";
  #    "..." = "cd ../..";
  #    "dc" = "docker compose";
  #    "ddie" = "docker system prune -a --volumes";
  #    "de" = "docker exec -it";
  #    "dnin" = "docker network inspect";
  #    "dnls" = "docker network ls";
  #    "dps" = "docker ps";
  #    "fd" = "fd -c never"; # never use color output on fd
  #    "g" = "git";
  #    "ll" = "ls -l";
  #    "ls" = "ls --color=auto";
  #    "nd" = "nix develop";
  #    "zits" = "sudo nixos-rebuild switch --flake .#zits";
  #  };
  #  promptInit = ''
  #    export GIT_PS1_SHOWDIRTYSTATE=1
  #    export GIT_PS1_SHOWSTASHSTATE=1
  #    export GIT_PS1_SHOWCOLORHINTS=1
  #    export GIT_PS1_SHOWUPSTREAM="auto"
  #    setopt PROMPT_SUBST
  #    autoload -U colors && colors
  #    source $HOME/.git-prompt.sh
  #    eval "$(direnv hook zsh)"
  #    bindkey -e
  #    if [[ "$SSH_TTY" ]]; then
  #      export PS1='%F{#C600E8}SSH on %m%f %F{magenta}%n%f %B%F{red}%~%f $(__git_ps1 "(%s) ")%b%# '
  #    else
  #      export PS1='%F{magenta}%n%f %B%F{blue}%~%f $(__git_ps1 "(%s) ")%b%# '
  #    fi;
  #  '';
  #};

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
    libreoffice
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
    xorg.libXft
    xorg.xev
    xorg.xmodmap
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
