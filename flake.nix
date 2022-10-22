{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable }@inputs: {
    nixosConfigurations."vm.strangervm.ts.hillion.co.uk" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/vm.strangervm.ts.hillion.co.uk/default.nix
        {
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        }
      ];
    };

    nixosConfigurations."microserver.parents.ts.hillion.co.uk" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/microserver.parents.ts.hillion.co.uk/default.nix
        {
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        }
      ];
    };

    nixosConfigurations."microserver.home.ts.hillion.co.uk" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/microserver.home.ts.hillion.co.uk/default.nix
        {
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        }
      ];
    };
  };
}
