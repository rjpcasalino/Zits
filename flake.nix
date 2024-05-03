{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = { 
      url = "github:nixos/nixpkgs/nixos-unstable"; 
    };
    home-manager = {
      url = "github:nix-community/home-manager";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, ... }@inputs: {
    nixosModules = { };
    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = with self.nixosModules; [
        ./configuration.nix
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.rjpc = import ./home.nix;
        }
      ];
    };
  };
}
