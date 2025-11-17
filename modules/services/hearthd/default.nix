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

    services.hearthd = {
      enable = true;

      secretConfigs = with config.age; [
        secrets."hearthd/locations.toml".path
      ];
      config = {
        logging = {
          level = "info";
          overrides = {
            "hearthd" = "debug";
          };
        };

        locations.default = "home";
      };
    };
  };
}
