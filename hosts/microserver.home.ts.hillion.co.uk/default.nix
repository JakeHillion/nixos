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
    networking.domain = "home.ts.hillion.co.uk";

    # Networking
    ## Tailscale
    age.secrets."tailscale/microserver.home.ts.hillion.co.uk".file = ../../secrets/tailscale/microserver.home.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/microserver.home.ts.hillion.co.uk".path;
      advertiseRoutes = [ "10.64.50.0/24" "10.239.19.0/24" ];
      advertiseExitNode = true;
    };

    ## Enable IoT VLAN
    networking.vlans = {
      vlan2 = {
        id = 2;
        interface = "eth0";
      };
    };

    ## Enable IP forwarding for Tailscale
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
    };

    ## Set up simpleproxy to Zigbee bridge
    systemd.services.zigbee-simpleproxy = {
      description = "Simple TCP Proxy for Zigbee Bridge";

      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = with pkgs; "${simpleproxy}/bin/simpleproxy -L 100.105.131.47:8888 -R 10.239.19.40:8888 -v";
        Restart = "always";
        RestartSec = 10;
      };
    };
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8888 ];

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;
  };
}

