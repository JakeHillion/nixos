{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-smh11ssli-epyc7k62/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.tang.enable = true;

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

