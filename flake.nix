{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs"; };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Accepting unexpected attributes in argument set i.e., @
  outputs = inputs@{ self, nixpkgs, home-manager, sops-nix, ... }: {
    nixosModules = {
      gnome = { pkgs, ... }: {
        config = {
          services.xserver.desktopManager.gnome.enable = false;
          services.gnome.core-utilities.enable = true;
          services.gnome.core-shell.enable = true;
          services.gnome.core-developer-tools.enable = true;
          environment.gnome.excludePackages =
            (with pkgs; [ gnome-photos gnome-tour ]) ++ (with pkgs.gnome; [
              gedit # text editor
              epiphany # web browser
              geary # email reader
              tali # poker game
              iagno # go game
              hitori # sudoku game
              atomix # puzzle game
              yelp # Help view
              gnome-contacts
              gnome-music
              gnome-initial-setup
            ]);
          programs.dconf.enable = true;
          programs.gnome-terminal.enable = false;
          # FIXME
          # see which of these is included in either
          # core-utilities or core-shell or core-dev
          environment.systemPackages = with pkgs; [
            gnome.gnome-settings-daemon
            gnome.gnome-tweaks
            gnome.gnome-session
          ];
        };
      };
    };
    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = with self.nixosModules; [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        gnome
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.truman = import ./home.nix;

          # Optionally, use home-manager.extraSpecialArgs to pass
          # arguments to home.nix
        }
        sops-nix.nixosModules.sops
      ];
    };
  };
}
