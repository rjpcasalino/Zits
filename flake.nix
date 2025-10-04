{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = {
      # unstable
      url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
      # stable
      # url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
    determinate = {
      url = "https://api.flakehub.com/f/DeterminateSystems/determinate/*";
    };
  };

  outputs = { self, nixpkgs, determinate, sops-nix, ... }@inputs: {
    nixosModules = { };
    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = with self.nixosModules; [
        ./configuration.nix
        sops-nix.nixosModules.sops
        determinate.nixosModules.default
      ];
    };
  };
}
