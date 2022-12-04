{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix }@inputs: {
    nixosConfigurations."gendry.jakehillion-terminals.ts.hillion.co.uk" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/gendry.jakehillion-terminals.ts.hillion.co.uk/default.nix
        agenix.nixosModule
        {
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        }
      ];
    };

    nixosConfigurations."vm.strangervm.ts.hillion.co.uk" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/vm.strangervm.ts.hillion.co.uk/default.nix
        agenix.nixosModule
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
        agenix.nixosModule
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
        agenix.nixosModule
        {
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        }
      ];
    };
  };
}
