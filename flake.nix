{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-chia.url = "github:lourkeur/nixpkgs?rev=e2b683787475d344892bddea9ab413dc611b894e";

    flake-utils.url = "github:numtide/flake-utils";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence/master";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-chia, flake-utils, agenix, home-manager, impermanence, ... }@inputs: {
    nixosConfigurations =
      let
        fqdns = builtins.attrNames (builtins.readDir ./hosts);
        getSystemOverlays = system: nixpkgsConfig: [
          (final: prev: {
            "storj" = final.callPackage ./pkgs/storj.nix { };
          })
        ];
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
              impermanence.nixosModules.impermanence

              home-manager.nixosModules.default
              {
                home-manager.sharedModules = [
                  impermanence.nixosModules.home-manager.impermanence
                ];
              }

              ({ config, ... }: {
                nix.registry.nixpkgs.flake = nixpkgs; # pin `nix shell` nixpkgs
                system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
                nixpkgs.overlays = getSystemOverlays config.nixpkgs.hostPlatform.system config.nixpkgs.config;
              })
            ];
          };
      in
      nixpkgs.lib.genAttrs fqdns mkHost;
  } // flake-utils.lib.eachDefaultSystem (system: {
    formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
  });
}
