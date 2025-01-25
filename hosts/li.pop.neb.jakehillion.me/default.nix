{ config, pkgs, lib, nixos-hardware, ... }:

{
  imports = [
    "${nixos-hardware}/raspberry-pi/4/default.nix"
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "23.11";

    networking.hostName = "li";
    networking.domain = "pop.neb.jakehillion.me";

    custom.defaults = true;

    ## Custom Services
    custom.locations.autoServe = true;

    # Networking
    ## Tailscale
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      extraUpFlags = [ "--advertise-routes" "192.168.1.0/24" ];
    };

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" "neb.jh" ];

      interfaces = {
        "end0" = {
          allowedTCPPorts = [
            22 # SSH
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

