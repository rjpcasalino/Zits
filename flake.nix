{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
                url = github:nix-community/home-manager;
                inputs.nixpkgs.follows = "nixpkgs";
          };
  };

  outputs = { self, nixpkgs, home-manager }: {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
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
