{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";

    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence/master";

    deploy-rs.url = "github:serokell/deploy-rs/master";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.inputs.utils.follows = "flake-utils";
  };

  description = "Hillion Nix flake";

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, agenix, home-manager, impermanence, deploy-rs, ... }@inputs: {
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
      
    deploy = {
      nodes = builtins.mapAttrs
        (name: value: {
          hostname = name;
          profiles.system = {
            user = "root";
            remoteBuild = true;
            path = deploy-rs.lib.aarch64-darwin.activate.nixos self.nixosConfigurations.${name};
          };
        })
        self.nixosConfigurations;
    };

    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  } // flake-utils.lib.eachDefaultSystem (system: {
    formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
  });
}
