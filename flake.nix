{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:JakeHillion/nixpkgs2/nixos-unstable";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    flake-utils.url = "github:numtide/flake-utils";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "darwin";
    agenix.inputs.home-manager.follows = "home-manager";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence/master";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    ogygia.url = "github:JakeHillion/ogygia-nix";
    ogygia.inputs.nixpkgs.follows = "nixpkgs";

    hearthd.url = "github:JakeHillion/hearthd";
    hearthd.inputs.nixpkgs.follows = "nixpkgs";

    status-jakehillion-me.url = "https://gitea.hillion.co.uk/JakeHillion/status.jakehillion.me/archive/main.tar.gz";
    status-jakehillion-me.inputs.nixpkgs.follows = "nixpkgs";

    qnaplcd-menu.url = "github:stephenhouser/QnapLCD-Menu";
    qnaplcd-menu.flake = false;
  };

  description = "Hillion Nix flake";

  outputs =
    { self
    , agenix
    , darwin
    , disko
    , flake-utils
    , hearthd
    , home-manager
    , home-manager-unstable
    , impermanence
    , nixos-generators
    , nixos-hardware
    , nixpkgs
    , nixpkgs-unstable
    , ogygia
    , qnaplcd-menu
    , status-jakehillion-me
    , ...
    }@inputs:
    let
      getSystemOverlays = system: nixpkgsConfig: [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (prev) system;
            config = {
              allowUnfree = true;
            };
          };

          "storj" = final.callPackage ./pkgs/storj.nix { };
          "pbcli" = final.callPackage ./pkgs/pbcli.nix { };
          "caddy-cloudflare" = prev.caddy.withPlugins {
            plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
            hash = "sha256-3NTI1fMlkpDB2Q/Q/CznEafscypEjJAOmTfAqWhHK1w=";
          };
          "ogygia" = ogygia.packages.${final.system}.ogygia;
          "qnaplcd" = final.callPackage ./pkgs/qnaplcd.nix { inherit qnaplcd-menu; };
        })
      ];
    in
    {
      nixosConfigurations =
        let
          fqdns = builtins.attrNames (builtins.readDir ./hosts);
          mkHost = fqdn:
            let
              system = nixpkgs.lib.strings.trim (builtins.readFile ./hosts/${fqdn}/system);
              func = if builtins.pathExists ./hosts/${fqdn}/unstable then nixpkgs-unstable.lib.nixosSystem else nixpkgs.lib.nixosSystem;
              home-manager-pick = if builtins.pathExists ./hosts/${fqdn}/unstable then home-manager-unstable else home-manager;
            in
            func {
              inherit system;
              specialArgs = inputs;
              modules = [
                ./hosts/${fqdn}
                ./modules

                agenix.nixosModules.default
                disko.nixosModules.disko
                hearthd.nixosModules.default
                impermanence.nixosModules.impermanence
                nixos-generators.nixosModules.all-formats
                ogygia.nixosModules.default

                home-manager-pick.nixosModules.default
                {
                  home-manager.sharedModules = [
                    impermanence.nixosModules.home-manager.impermanence
                  ];
                }

                ({ config, lib, ... }: {
                  system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
                  nixpkgs.overlays = getSystemOverlays config.nixpkgs.hostPlatform.system config.nixpkgs.config;

                  networking = let parts = lib.splitString "." fqdn; in {
                    hostName = builtins.head parts;
                    domain = lib.concatStringsSep "." (builtins.tail parts);
                  };
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

    } // flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = getSystemOverlays system { };
        config = { allowUnfree = true; };
      };
    in
    {
      formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

      packages.caddy-cloudflare = pkgs.caddy-cloudflare;
    });
}
