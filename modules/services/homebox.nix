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
      owner = "homebox";
      group = "homebox";
    };

    users.users.homebox.uid = config.ids.uids.homebox;
    users.groups.homebox.gid = config.ids.gids.homebox;

    systemd.tmpfiles.rules = lib.optionals config.custom.impermanence.enable [
      "d ${config.custom.impermanence.base}/services/homebox 0750 homebox homebox -"
    ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."homebox.neb.jakehillion.me" = {
        extraConfig = ''
          reverse_proxy http://localhost:7745
        '';
      };
    };

    services.restic.backups."homebox" = {
      repository = "rest:https://restic.neb.jakehillion.me/mig29";
      user = "homebox";
      passwordFile = config.age.secrets."homebox/restic/mig29.key".path;

      timerConfig = {
        OnBootSec = "60m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "5m";
      };

      paths = [ config.services.homebox.settings.HBOX_STORAGE_DATA ];
    };

    services.homebox = {
      enable = true;
      database.createLocally = true;
      settings = {
        HBOX_WEB_PORT = "7745";
        HBOX_WEB_HOST = "127.0.0.1";
        HBOX_OPTIONS_ALLOW_REGISTRATION = "true";
      } // lib.optionalAttrs config.custom.impermanence.enable {
        HBOX_STORAGE_DATA = "${config.custom.impermanence.base}/services/homebox";
      };
    };
  };
}
