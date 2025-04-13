{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-beelink-eq14/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;
    custom.tang.enable = true;

    ## CA server
    custom.ca.service.enable = true;

    networking = {
      vlans = {
        iot = {
          id = 2;
          interface = "enp2s0";
        };
      };
    };
  };
}
