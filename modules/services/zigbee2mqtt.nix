{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.zigbee2mqtt;
in
{
  options.custom.services.zigbee2mqtt = {
    enable = lib.mkEnableOption "zigbee2mqtt";

    backup = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."mqtt/zigbee2mqtt.yaml" = {
      file = ../../secrets/mqtt/zigbee2mqtt.age;
      owner = "zigbee2mqtt";
    };

    services.caddy = {
      enable = true;

      virtualHosts."zigbee2mqtt.home.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }
          reverse_proxy http://127.0.0.1:15606
        '';
      };
    };

    services.zigbee2mqtt = {
      enable = true;
      settings = {
        permit_join = false;
        mqtt = {
          server = "mqtt://router.home.ts.hillion.co.uk:1883";
          user = "zigbee2mqtt";
          password = "!${config.age.secrets."mqtt/zigbee2mqtt.yaml".path} password";
        };
        serial = {
          port = "/dev/ttyUSB0";
        };
        frontend = {
          port = 15606;
          url = "http://zigbee2mqtt.home.neb.jakehillion.me";
        };
        homeassistant = true;
        advanced = {
          channel = 15;
        };
      };
    };

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          users = {
            zigbee2mqtt = {
              acl = [ "readwrite #" ];
              hashedPassword = "$7$101$ZrD6C+b7Xo/fUoGw$Cf/6Xm52Syv2G+5+BqpUWRs+zrTrTvBL9EFzks9q/Q6ZggXVcp+Bi3ZpmQT5Du9+42G30Y7G3hWpYbA8j1ooWg==";
            };
            homeassistant = {
              acl = [ "readwrite #" ];
              hashedPassword = "$7$101$wGQZPdVdeW7iQFmH$bK/VOR6LXCLJKbb6M4PNeVptocjBAWXCLMtEU5fQNBr0Y5UAWlhVg8UAu4IkIXgnViI51NnhXKykdlWF63VkVQ==";
            };
          };
        }
      ];
    };

    age.secrets."resilio/zigbee2mqtt/1.6T.key" = lib.mkIf cfg.backup {
      file = ../../secrets/restic/1.6T.age;
      owner = "zigbee2mqtt";
    };

    services.restic.backups."zigbee2mqtt" = lib.mkIf cfg.backup {
      repository = "rest:https://restic.neb.jakehillion.me/1.6T";
      user = "zigbee2mqtt";
      passwordFile = config.age.secrets."resilio/zigbee2mqtt/1.6T.key".path;

      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "1d";
        RandomizedDelaySec = "1h";
      };

      paths = [ config.services.zigbee2mqtt.dataDir ];
    };
  };
}
