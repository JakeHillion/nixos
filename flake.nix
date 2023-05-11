{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-22.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, agenix, home-manager, darwin, ... }@inputs: {
    nixosConfigurations =
      let
        fqdns = builtins.attrNames (builtins.readDir ./hosts);
        isNixos = fqdn: !builtins.pathExists ./hosts/${fqdn}/darwin;
        mkHost = fqdn:
          let system = builtins.readFile ./hosts/${fqdn}/system;
          in
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = inputs;
            modules = [
              ./hosts/${fqdn}/default.nix
              ./modules/default.nix
              agenix.nixosModules.default
              home-manager.nixosModules.default
              {
                system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
              }
            ];
          };
      in
      nixpkgs.lib.genAttrs (builtins.filter isNixos fqdns) mkHost;

    darwinConfigurations =
      let
        hosts = builtins.attrNames (builtins.readDir ./hosts);
        isDarwin = host: builtins.pathExists ./hosts/${host}/darwin;
        mkHost = host:
          let system = builtins.readFile ./hosts/${host}/system;
          in
          darwin.lib.darwinSystem {
            inherit system;
            inherit inputs;
            modules = [
              ./hosts/${host}/default.nix
              agenix.darwinModules.default
              home-manager.darwinModules.default
            ];
          };
      in
      nixpkgs.lib.genAttrs (builtins.filter isDarwin hosts) mkHost;

    formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    formatter."aarch64-darwin" = nixpkgs.legacyPackages."aarch64-darwin".nixpkgs-fmt;
  };
}
