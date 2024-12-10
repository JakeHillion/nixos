{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/4/default.nix"
    ./hardware-configuration.nix
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
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" "neb.jh" ];

      interfaces = {
        "eth0" = {
          allowedUDPPorts = [
          ];
          allowedTCPPorts = [
            7654 # Tang
          ];
        };
      };
    };
  };
}

