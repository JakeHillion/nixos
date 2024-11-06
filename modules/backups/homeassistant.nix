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
    age.secrets."backups/homeassistant/restic/1.6T" = {
      file = ../../secrets/restic/1.6T.age;
      owner = "postgres";
      group = "postgres";
    };

    services = {
      postgresqlBackup = {
        enable = true;
        compression = "none"; # for better diffing
        databases = [ "homeassistant" ];
      };

      restic.backups = {
        "homeassistant-config" = {
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
        "homeassistant-database" = {
          user = "postgres";
          timerConfig = {
            OnCalendar = "03:00";
            RandomizedDelaySec = "60m";
          };
          repository = "rest:https://restic.ts.hillion.co.uk/1.6T";
          passwordFile = config.age.secrets."backups/homeassistant/restic/1.6T".path;
          paths = [
            "${config.services.postgresqlBackup.location}/homeassistant.sql"
          ];
        };
      };
    };
  };
}

