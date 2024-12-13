{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/4/default.nix"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "li";
    networking.domain = "pop.ts.hillion.co.uk";

    custom.defaults = true;

    ## Custom Services
    custom.locations.autoServe = true;

    # Networking
    ## Tailscale
    age.secrets."tailscale/li.pop.ts.hillion.co.uk".file = ../../secrets/tailscale/li.pop.ts.hillion.co.uk.age;
    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets."tailscale/li.pop.ts.hillion.co.uk".path;
      useRoutingFeatures = "server";
      extraUpFlags = [ "--advertise-routes" "192.168.1.0/24" ];
    };

    ## Enable ZRAM to make up for 2GB of RAM
    zramSwap = {
      enable = true;
      memoryPercent = 200;
      algorithm = "zstd";
    };

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" "neb.jh" ];

      interfaces = {
        "end0" = {
          allowedTCPPorts = [
            7654 # Tang
          ];
          allowedUDPPorts = [
            4242 # Nebula Lighthouse
          ];
        };
      };
    };
  };
}

