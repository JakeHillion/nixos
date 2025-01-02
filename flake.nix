{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "https://gitea.hillion.co.uk/JakeHillion/nixpkgs/archive/nixos-unstable.tar.gz";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    flake-utils.url = "github:numtide/flake-utils";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "darwin";
    agenix.inputs.home-manager.follows = "home-manager";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence/master";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  description = "Hillion Nix flake";

  outputs =
    { self
    , agenix
    , darwin
    , disko
    , flake-utils
    , home-manager
    , home-manager-unstable
    , impermanence
    , nixos-hardware
    , nixpkgs
    , nixpkgs-unstable
    , ...
    }@inputs:
    let
      getSystemOverlays = system: nixpkgsConfig: [
        (final: prev: {
          unstable = nixpkgs-unstable.legacyPackages.${prev.system};

          "inventree" = final.callPackage ./pkgs/inventree.nix { };
          "storj" = final.callPackage ./pkgs/storj.nix { };
        })
      ];
    in
    {
      nixosConfigurations =
        let
          fqdns = builtins.attrNames (builtins.readDir ./hosts);
          mkHost = fqdn:
            let
              system = builtins.readFile ./hosts/${fqdn}/system;
              func = if builtins.pathExists ./hosts/${fqdn}/unstable then nixpkgs-unstable.lib.nixosSystem else nixpkgs.lib.nixosSystem;
              home-manager-pick = if builtins.pathExists ./hosts/${fqdn}/unstable then home-manager-unstable else home-manager;
            in
            func {
              inherit system;
              specialArgs = inputs;
              modules = [
                ./hosts/${fqdn}/default.nix
                ./modules/default.nix

                agenix.nixosModules.default
                impermanence.nixosModules.impermanence
                disko.nixosModules.disko

                home-manager-pick.nixosModules.default
                {
                  home-manager.sharedModules = [
                    impermanence.nixosModules.home-manager.impermanence
                  ];
                }

                ({ config, ... }: {
                  system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
                  nixpkgs.overlays = getSystemOverlays config.nixpkgs.hostPlatform.system config.nixpkgs.config;
                })
              ];
            };
        in
        nixpkgs.lib.genAttrs fqdns mkHost;

      darwinConfigurations = {
        jakehillion-mba-m2-15 = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = inputs;

          modules = [
            ./darwin/jakehillion-mba-m2-15/configuration.nix

            ({ config, ... }: {
              nixpkgs.overlays = getSystemOverlays "aarch64-darwin" config.nixpkgs.config;
            })
          ];
        };
      };

    } // flake-utils.lib.eachDefaultSystem (system: {
      formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    });
}
