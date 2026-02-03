{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.immich;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "immich";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."immich/restic/b52.key" = {
      file = ../../secrets/restic/b52.age;
      owner = "immich";
      group = "immich";
    };

    users.users.immich.uid = config.ids.uids.immich;
    users.groups.immich.gid = config.ids.gids.immich;

    custom.www.nebula = {
      enable = true;
      virtualHosts."immich.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://localhost:${toString config.services.immich.port}
      '';
    };

    services.restic.backups."immich" = {
      repository = "rest:https://restic.${config.ogygia.domain}/b52";
      user = "immich";
      passwordFile = config.age.secrets."immich/restic/b52.key".path;

      timerConfig = {
        OnBootSec = "60m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "5m";
      };

      paths = [ config.services.immich.mediaLocation ];
    };

    services.immich = {
      enable = true;
    };
  };
}
