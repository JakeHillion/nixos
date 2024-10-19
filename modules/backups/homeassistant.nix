{ config, pkgs, lib, ... }:

let
  cfg = config.custom.backups.homeassistant;
in
{
  options.custom.backups.homeassistant = {
    enable = lib.mkEnableOption "homeassistant";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."backups/homeassistant/restic/128G" = {
      file = ../../secrets/restic/128G.age;
      owner = "hass";
      group = "hass";
    };

    services = {
      restic.backups."homeassistant" = {
        user = "hass";
        timerConfig = {
          OnCalendar = "03:00";
          RandomizedDelaySec = "60m";
        };
        repository = "rest:https://restic.ts.hillion.co.uk/128G";
        passwordFile = config.age.secrets."backups/homeassistant/restic/128G".path;
        paths = [
          config.services.home-assistant.configDir
        ];
      };
    };
  };
}

