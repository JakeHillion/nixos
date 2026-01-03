{ config, lib, ... }:

let
  cfg = config.custom.services.hearthd;
in
{
  options.custom.services.hearthd = {
    enable = lib.mkEnableOption "hearthd";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."hearthd/locations.toml".file = ./locations.toml.age;
    age.secrets."hearthd/mqtt.toml".file = ./mqtt.toml.age;

    services.hearthd = {
      enable = true;

      secretConfigs = with config.age; [
        secrets."hearthd/locations.toml".path
        secrets."hearthd/mqtt.toml".path
      ];
      config = {
        logging = {
          level = "info";
          overrides = {
            "hearthd" = "debug";
          };
        };

        locations.default = "home";

        http = {
          listen = config.custom.dns.nebula.ipv4;
          port = 8565;
        };

        integrations.mqtt = {
          broker = "mqtt.home.${config.ogygia.domain}";
          port = 1883;
          client_id = "hearthd";
          discovery_prefix = "homeassistant";
          username = "hearthd";
        };
      };
    };
  };
}
