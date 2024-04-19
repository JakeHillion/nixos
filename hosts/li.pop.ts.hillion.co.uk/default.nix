{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common/default.nix
    ../../modules/rpi/rpi4.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "li";
    networking.domain = "pop.ts.hillion.co.uk";

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
  };
}

