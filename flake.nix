{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?rev=b68a6a27adb452879ab66c0eaac0c133e32823b2";
    nixpkgs-unstable.url = "github:nixos/nixpkgs?rev=52b2ac8ae18bbad4374ff0dd5aeee0fdf1aea739";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix }@inputs: {
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
