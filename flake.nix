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
          services.xserver.desktopManager.gnome.enable = false;
          services.xserver.displayManager.startx.enable = true;
          services.gnome.core-utilities.enable = true;
          services.gnome.core-shell.enable = true;
          services.gnome.core-developer-tools.enable = true;
          # FIXME?
          # I think this oddness with pkgs and with pkgs.gnome
          # is due to how to gnome packages "just are" in nixpkgs
          environment.gnome.excludePackages = (with pkgs; [ gnome-photos gnome-tour ])
            ++ (with pkgs.gnome; [
              # cheese # webcam tool
              # gedit # text editor
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
          programs.gnome-terminal.enable = true;
          # I guess never assume so even if package is removed
          # from exludePackages it still needs to be added
          environment.systemPackages = with pkgs; [
            gnome.gnome-control-center
            gnome-icon-theme
            gnome.gnome-tweaks
            gnome.gnome-session
            gnome.cheese # webcam tool
            gnome.gedit
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
      ];
    };
  };
}
