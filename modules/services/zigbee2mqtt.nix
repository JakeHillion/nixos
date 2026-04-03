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
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ config.services.zigbee2mqtt.dataDir ];

    age.secrets."mqtt/zigbee2mqtt.yaml" = {
      file = ../../secrets/mqtt/zigbee2mqtt.age;
      owner = "zigbee2mqtt";
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."zigbee2mqtt.home.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:15606
      '';
    };

    services.zigbee2mqtt = {
      enable = true;
      settings = {
        permit_join = false;
        mqtt = {
          server = "mqtt://mqtt.home.${config.ogygia.domain}:1883";
          user = "zigbee2mqtt";
          password = "!${config.age.secrets."mqtt/zigbee2mqtt.yaml".path} password";
        };
        serial = {
          port = "/dev/ttyUSB0";
        };
        frontend = {
          port = 15606;
          url = "http://zigbee2mqtt.home.${config.ogygia.domain}";
        };
        homeassistant.enabled = true;
        advanced = {
          channel = 15;
        };
      };
    };


    age.secrets."restic/zigbee2mqtt/b52.key" = lib.mkIf cfg.backup {
      rekeyFile = ../../secrets/restic/b52.age;
      owner = "zigbee2mqtt";
    };

    services.restic.backups."zigbee2mqtt" = lib.mkIf cfg.backup {
      repository = "rest:https://restic.${config.ogygia.domain}/b52";
      user = "zigbee2mqtt";
      passwordFile = config.age.secrets."restic/zigbee2mqtt/b52.key".path;

      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "1d";
        RandomizedDelaySec = "1h";
      };

      paths = [ config.services.zigbee2mqtt.dataDir ];
    };
  };
}
