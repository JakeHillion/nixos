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

    ## Run a persistent iperf3 server
    services.iperf3.enable = true;
    services.iperf3.openFirewall = true;

    ## Home automation
    age.secrets."mqtt/zigbee2mqtt.yaml" = {
      file = ../../secrets/mqtt/zigbee2mqtt.age;
      owner = "zigbee2mqtt";
    };

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          users.zigbee2mqtt = {
            acl = [ "readwrite #" ];
            hashedPassword = "$7$101$ZrD6C+b7Xo/fUoGw$Cf/6Xm52Syv2G+5+BqpUWRs+zrTrTvBL9EFzks9q/Q6ZggXVcp+Bi3ZpmQT5Du9+42G30Y7G3hWpYbA8j1ooWg==";
          };
        }
      ];
    };
    services.zigbee2mqtt = {
      enable = true;
      settings = {
        permit_join = false;
        mqtt = {
          server = "mqtt://microserver.home.ts.hillion.co.uk:1883";
          user = "zigbee2mqtt";
          password = "!${config.age.secrets."mqtt/zigbee2mqtt.yaml".path} password";
        };
        serial = {
          port = "/dev/ttyUSB0";
        };
        frontend = true;
        advanced = {
          channel = 15;
        };
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      1883 # MQTT server
      8080 # Zigbee2MQTT frontend
      8888 # Zigbee bridge simple proxy
    ];
  };
}

