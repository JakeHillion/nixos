{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-vul-vhp-1c-1gb
  ];

  config = {
    system.stateVersion = "25.05";

    # Enable defaults and auto-serve
    custom.defaults = true;
    custom.locations.autoServe = true;
    custom.auto_updater.allowReboot = true;

    # Tang/Clevis configuration for disk encryption
    custom.tang.enable = true;

    # Networking
    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
    };
  };
}
