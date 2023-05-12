{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      #url = github:nix-community/home-manager/release-22.11;
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Accepting unexpected attributes in argument set i.e., @
  outputs = inputs@{ self, nixpkgs, home-manager, ... }: {
    nixosModules = {
      gnome = { pkgs, ... }: {
        config = {
          services.xserver.enable = true;
          services.xserver.desktopManager.gnome.enable = true;
          services.xserver.displayManager.startx.enable = true;
          environment.gnome.excludePackages =
            (with pkgs; [ gnome-photos gnome-tour ]) ++ (with pkgs.gnome; [
              cheese # webcam tool
              gnome-music
              gedit # text editor
              epiphany # web browser
              geary # email reader
              gnome-characters
              tali # poker game
              iagno # go game
              hitori # sudoku game
              atomix # puzzle game
              yelp # Help view
              gnome-contacts
              gnome-initial-setup
            ]);
          programs.dconf.enable = true;
          environment.systemPackages = with pkgs; [ gnome.gnome-tweaks ];
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
      ];
    };
  };
}
