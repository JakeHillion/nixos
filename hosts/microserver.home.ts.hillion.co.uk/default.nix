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

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      1883 # MQTT server
    ];

    ## HomeKit
    systemd.services.homekit-simpleproxy = {
      description = "Simple TCP Proxy for HomeKit";

      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = with pkgs; "${simpleproxy}/bin/simpleproxy -L 21063 -R 100.85.235.32:21063 -v";
        Restart = "always";
        RestartSec = 10;
      };
    };
    networking.firewall.interfaces."eth0".allowedTCPPorts = [ 21063 ];

    ## mDNS Entry for HomeKit
    services.avahi = {
      enable = true;
      publish = {
        enable = true;
      };
      extraServiceFiles = {
        hap = ''
          <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">%h</name>
            <service>
              <type>_hap._tcp</type>
              <port>21063</port>
            </service>
          </service-group>
        '';
      };
    };
  };
}

