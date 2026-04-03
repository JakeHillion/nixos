{ config, lib, ... }:

let
  cfg = config.custom.services.firefly-iii;
in
{
  options.custom.services.firefly-iii = {
    enable = lib.mkEnableOption "firefly-iii";
  };

  config = lib.mkIf cfg.enable {
    users.users.firefly-iii.uid = config.ids.uids.firefly-iii;

    age.secrets."firefly-iii/app-key" = {
      file = ./app-key.age;
      owner = "firefly-iii";
      group = "caddy";
    };

    age.secrets."firefly-iii/restic/mig29" = {
      rekeyFile = ../../../secrets/restic/mig29.age;
    };

    services.firefly-iii.dataDir = lib.mkIf config.custom.impermanence.enable
      "${config.custom.impermanence.base}/services/firefly-iii";

    custom.www.nebula = {
      enable = true;
      virtualHosts."firefly.${config.ogygia.domain}" = {
        extraConfig = ''
          root * ${config.services.firefly-iii.package}/public
          php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket}
          file_server
        '';
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "firefly-iii" ];
      ensureUsers = [{
        name = "firefly-iii";
        ensureDBOwnership = true;
      }];
    };

    services.postgresqlBackup = {
      enable = true;
      compression = "none";
      databases = [ "firefly-iii" ];
    };

    services.restic.backups."firefly-iii" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:30";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."firefly-iii/restic/mig29".path;
      paths = [
        "${config.services.postgresqlBackup.location}/firefly-iii.sql"
        config.services.firefly-iii.dataDir
      ];
    };

    services.firefly-iii = {
      enable = true;
      group = "caddy";
      virtualHost = "firefly.${config.ogygia.domain}";
      settings = {
        APP_ENV = "production";
        APP_KEY_FILE = config.age.secrets."firefly-iii/app-key".path;
        DB_CONNECTION = "pgsql";
        DB_DATABASE = "firefly-iii";
        DB_USERNAME = "firefly-iii";
        SITE_OWNER = "mail@jakehillion.me";
      };
    };
  };
}
