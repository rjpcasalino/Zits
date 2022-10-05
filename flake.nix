{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }: {

    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.jdoe = import ./home.nix;

          # Optionally, use home-manager.extraSpecialArgs to pass
          # arguments to home.nix
        }
      ];
    };

    nixosConfigurations.truman = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          boot.isContainer = true;
          system.stateVersion = "22.05";


          # Network configuration.
          networking.useDHCP = false;
          networking.firewall.allowedTCPPorts = [ 80 ];

          # Enable a web server.
          services.httpd = {
            enable = true;
            adminAddr = "morty@example.org";
          };
        })
      ];
    };
  };
}
