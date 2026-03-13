{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:JakeHillion/nixpkgs2/nixos-unstable";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/nix-darwin-25.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "darwin";
    agenix.inputs.home-manager.follows = "home-manager";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

    impermanence.url = "github:nix-community/impermanence/4b3e914cdf97a5b536a889e939fb2fd2b043a170";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    ogygia.url = "github:JakeHillion/ogygia-nix";
    ogygia.inputs.nixpkgs.follows = "nixpkgs";

    async-coder.url = "git+https://gitea.hillion.co.uk/JakeHillion/async-coder.git";
    async-coder.inputs.nixpkgs.follows = "nixpkgs";

    hearthd.url = "github:JakeHillion/hearthd";
    hearthd.inputs.nixpkgs.follows = "nixpkgs";

    status-jakehillion-me.url = "https://gitea.hillion.co.uk/JakeHillion/status.jakehillion.me/archive/main.tar.gz";
    status-jakehillion-me.inputs.nixpkgs.follows = "nixpkgs";

    personal-agent.url = "git+https://gitea.hillion.co.uk/JakeHillion/personal-agent.git";
    personal-agent.inputs.nixpkgs.follows = "nixpkgs";

    qnaplcd-menu.url = "github:stephenhouser/QnapLCD-Menu";
    qnaplcd-menu.flake = false;
  };

  description = "Hillion Nix flake";

  outputs =
    { self
    , agenix
    , async-coder
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
    , personal-agent
    , qnaplcd-menu
    , status-jakehillion-me
    , treefmt-nix
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
          "caddy-with-dns" = final.callPackage ./pkgs/caddy-with-dns { };
          "ogygia" = ogygia.packages.${final.system}.ogygia;
          "qnaplcd" = final.callPackage ./pkgs/qnaplcd.nix { inherit qnaplcd-menu; };
          "opencode-plugin" = final.callPackage ./pkgs/opencode-plugin { };
        })
      ];
      mkSystem = import ./lib/mkSystem.nix { inherit inputs; };
      treefmtEval = pkgs: treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.gofumpt.enable = true;
        programs.black.enable = true;
        settings.formatter.black.options = [ "--line-length" "79" ];
      };
    in
    {
      inherit mkSystem;

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
              modules = mkSystem.modules home-manager-pick ++ [
                ./hosts/${fqdn}

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

    } // nixpkgs.lib.recursiveUpdate
      (nixpkgs.lib.recursiveUpdate
        (flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = getSystemOverlays system { };
            config = { allowUnfree = true; };
          };
        in
        {
          formatter = (treefmtEval pkgs).config.build.wrapper;

          checks = {
            formatting = (treefmtEval pkgs).config.build.check self;
          };

          packages.caddy-with-dns = pkgs.caddy-with-dns;
        }))
        (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = getSystemOverlays system { };
              config = { allowUnfree = true; };
            };
          in
          {
            # npm tooling doesn't work on Darwin, only build on Linux
            checks.opencode-plugin = pkgs.opencode-plugin;
          }
        )))
      (flake-utils.lib.eachSystem [ "x86_64-linux" ] (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = getSystemOverlays system { };
            config = { allowUnfree = true; };
          };
        in
        {
          # NixOS module tests
          checks = import ./tests {
            inherit pkgs system inputs;
            lib = nixpkgs.lib;
          };

          # App to auto-generate all snapshots: `nix run .#generate-snapshots`
          apps.generate-snapshots = {
            type = "app";
            program = "${import ./tests/generate-snapshots.nix {
            inherit pkgs system inputs;
            lib = nixpkgs.lib;
          }}/bin/generate-snapshots";
          };
        }
      ));
}
