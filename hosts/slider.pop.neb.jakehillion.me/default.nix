{ config, pkgs, lib, ... }:

{
  imports = [
    ../../models/t0-oci
  ];

  config = {
    system.stateVersion = "25.05";

    custom.defaults = true;
    custom.auto-updater.allowReboot = true;
    custom.locations.autoServe = true;

    custom.tang.enable = true;

    # Accept remote builds from devboxes
    custom.services.nix-remote-builder = {
      enable = true;
      authorizedHosts = [
        "maverick.cx.neb.jakehillion.me"
        "rooster.cx.neb.jakehillion.me"
        "bob.lt.neb.jakehillion.me"
        "merlin.rig.neb.jakehillion.me"
      ];
    };

    # Knot DNS - public listen address
    services.knot.settings.server.listen = [
      "10.0.0.24@53"
    ];

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
          53 # DNS
        ];
        allowedUDPPorts = lib.mkForce [
          53 # DNS
        ];
      };
    };
  };
}
