{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-oci
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;
    custom.auto_updater.allowReboot = true;
    custom.locations.autoServe = true;

    custom.tang.enable = true;

    # Networking
    networking = {
      interfaces.eth0 = {
        ipv4.addresses = [{
          address = "10.0.0.24";
          prefixLength = 24;
        }];
      };
      defaultGateway = "10.0.0.1";

      firewall = {
        allowedTCPPorts = lib.mkForce [
          22 # SSH
        ];
        allowedUDPPorts = lib.mkForce [ ];
      };
    };
  };
}
