{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.immich;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "immich";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."immich/restic/1.6T.key" = {
      file = ../../secrets/restic/1.6T.age;
      owner = "immich";
      group = "immich";
    };

    users.users.immich.uid = config.ids.uids.immich;
    users.groups.immich.gid = config.ids.gids.immich;

    services.caddy = {
      enable = true;

      virtualHosts."immich.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          reverse_proxy http://localhost:${toString config.services.immich.port}

          tls {
            ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
          }
        '';
      };
    };

    services.restic.backups."immich" = {
      repository = "rest:https://restic.ts.hillion.co.uk/1.6T";
      user = "immich";
      passwordFile = config.age.secrets."immich/restic/1.6T.key".path;

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
