{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = {
      url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
      #url = "https://flakehub.com/f/NixOS/nixpkgs/0.2405.0";
      #url = "github:nixos/nixpkgs/nixos-unstable-small";
      #url = "github:nixos/nixpkgs/nixos-24.05-small";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/0.1.145.tar.gz";
    };
  };

  outputs = { self, nixpkgs, determinate, home-manager, sops-nix, ... }@inputs: {
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
        determinate.nixosModules.default
      ];
    };
  };
}
