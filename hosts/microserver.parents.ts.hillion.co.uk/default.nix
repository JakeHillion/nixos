{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common/default.nix
    ../../modules/rpi/rpi4.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "microserver";
    networking.domain = "parents.ts.hillion.co.uk";

    # Networking
    ## Tailscale
    age.secrets."tailscale/microserver.parents.ts.hillion.co.uk".file = ../../secrets/tailscale/microserver.parents.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/microserver.parents.ts.hillion.co.uk".path;
      advertiseRoutes = [ "192.168.1.0/24" ];
    };

    ## Enable IP forwarding for Tailscale
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
    };

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;
  };
}

