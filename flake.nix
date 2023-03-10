{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix, home-manager }@inputs: {
    nixosConfigurations =
      let
        fqdns = builtins.attrNames (builtins.readDir ./hosts);
        mkHost = fqdn:
          let system = builtins.readFile ./hosts/${fqdn}/system; in
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = inputs;
            modules = [
              ./hosts/${fqdn}/default.nix
              agenix.nixosModules.default
              home-manager.nixosModule
              {
                system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
              }
            ];
          };
      in
      nixpkgs.lib.genAttrs fqdns mkHost;

    formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    formatter."aarch64-darwin" = nixpkgs.legacyPackages."aarch64-darwin".nixpkgs-fmt;
  };
}
