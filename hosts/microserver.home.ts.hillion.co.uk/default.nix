{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/rpi/rpi4.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "microserver";
    networking.domain = "home.ts.hillion.co.uk";

    custom.defaults = true;

    ## Custom Services
    custom.locations.autoServe = true;

    # Networking
    ## Tailscale
    age.secrets."tailscale/microserver.home.ts.hillion.co.uk".file = ../../secrets/tailscale/microserver.home.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/microserver.home.ts.hillion.co.uk".path;
    };

    ## Enable IoT VLAN
    networking.vlans = {
      vlan2 = {
        id = 2;
        interface = "eth0";
      };
    };

    hardware = {
      bluetooth.enable = true;
    };

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    networking.nameservers = lib.mkForce [ ]; # Trust the DHCP nameservers
    networking.firewall.interfaces = {
      "eth0" = {
        allowedUDPPorts = [
          5353 # HomeKit
        ];
        allowedTCPPorts = [
          1400 # HA Sonos
          7654 # Tang
          21063 # HomeKit
        ];
      };
    };
  };
}

