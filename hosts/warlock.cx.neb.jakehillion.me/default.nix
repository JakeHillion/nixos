{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-beelink-eq14/default.nix
  ];

  config = {
    system.stateVersion = "24.11";

    custom.defaults = true;

    ## Custom Services
    custom.tang.enable = true;
    custom.auto_updater.allowReboot = true;

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
