{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.homebox;
in
{
  options.custom.services.homebox = {
    enable = lib.mkEnableOption "homebox";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."homebox/restic/mig29.key" = {
      file = ../../secrets/restic/mig29.age;
    };

    users.users.homebox.uid = config.ids.uids.homebox;
    users.groups.homebox.gid = config.ids.gids.homebox;

    systemd.tmpfiles.rules = lib.optionals config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/homebox 0750 homebox homebox -"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."homebox.${config.ogygia.domain}" = {
        extraConfig = ''
          reverse_proxy http://localhost:7745
        '';
      };
    };

    services.postgresqlBackup = {
      enable = true;
      compression = "none"; # for better diffing
      databases = [ "homebox" ];
    };

    services.restic.backups."homebox" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."homebox/restic/mig29.key".path;
      paths = [
        "${config.services.postgresqlBackup.location}/homebox.sql"
        (lib.removePrefix "file://" config.services.homebox.settings.HBOX_STORAGE_CONN_STRING)
      ];
    };

    services.homebox = {
      enable = true;
      database.createLocally = true;
      settings = {
        HBOX_WEB_PORT = "7745";
        HBOX_WEB_HOST = "127.0.0.1";
        HBOX_OPTIONS_ALLOW_REGISTRATION = "true";
      } // lib.optionalAttrs config.custom.impermanence.enable {
        HBOX_STORAGE_CONN_STRING = "file://${config.custom.impermanence.base}/services/homebox";
      };
    };
  };
}
