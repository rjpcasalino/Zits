{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs"; };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Accepting unexpected attributes in argument set i.e., @
  outputs = inputs@{ self, nixpkgs, sops-nix, ... }: {
    nixosModules = {};
    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = with self.nixosModules; [
        ./configuration.nix
        sops-nix.nixosModules.sops
      ];
    };
  };
}
