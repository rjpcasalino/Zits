{
  description = "A NixOS configuration for zits";

  inputs = {
    nixpkgs = {
      # https://flakehub.com/flake/NixOS/nixpkgs?view=usage
      # url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
      url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    waybar-themes = {
      url = "github:HANCORE-linux/waybar-themes";
      flake = false;
    };
    waybar-macos = {
      url = "github:kamlendras/waybar-macos-sequoia";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sops-nix, determinate, waybar-themes, waybar-macos, ... }@inputs: {
    nixosModules = { };
    nixosConfigurations.zits = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        sops-nix.nixosModules.sops
        determinate.nixosModules.default
      ];
    };
  };
}
