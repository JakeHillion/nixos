{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-smh11ssli-epyc7k62/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.tang.enable = true;
    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };

    ## Impermanence
    custom.impermanence = {
      enable = true;
      userExtraFiles.jake = [
        ".ssh/id_rsa"
        ".ssh/id_ecdsa"
      ];
    };

    # Allow performing emulated builds in QEMU
    boot.binfmt.emulatedSystems = [
      "aarch64-linux"
      "armv7l-linux"
    ];

    networking = {
      useDHCP = false;

      defaultGateway.address = "10.64.50.1";

      interfaces.eth0 = {
        ipv4 = {
          addresses = [{
            address = "10.64.50.20";
            prefixLength = 24;
          }];
        };
      };
    };
  };
}

