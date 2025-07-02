{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.radicale;
in
{
  options.custom.services.radicale = {
    enable = lib.mkEnableOption "radicale";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5232;
      description = "Port for Radicale to listen on";
    };

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
      description = "Enable backups to restic";
    };
  };

  config = lib.mkIf cfg.enable {

    age.secrets = {
      "backups/radicale/restic/128G" = lib.mkIf cfg.backup {
        file = ../../secrets/restic/128G.age;
        owner = "radicale";
        group = "radicale";
      };

      "radicale/users" = {
        file = ../../secrets/radicale/users.age;
        owner = "radicale";
        group = "radicale";
      };
    };

    users.users.radicale.uid = config.ids.uids.radicale;
    users.groups.radicale.gid = config.ids.gids.radicale;

    services = {
      restic.backups."radicale" = lib.mkIf cfg.backup {
        user = "radicale";
        timerConfig = {
          OnBootSec = "15m";
          OnUnitInactiveSec = "30m";
          RandomizedDelaySec = "5m";
        };
        repository = "rest:https://restic.neb.jakehillion.me/128G";
        passwordFile = config.age.secrets."backups/radicale/restic/128G".path;
        paths = [
          config.services.radicale.settings.storage.filesystem_folder
        ];
      };

      radicale = {
        enable = true;

        settings = {
          server = {
            hosts = [
              "127.0.0.1:${toString cfg.port}"
              "[::1]:${toString cfg.port}"
            ];
          };

          auth = {
            type = "htpasswd";
            htpasswd_filename = config.age.secrets."radicale/users".path;
            htpasswd_encryption = "sha512";
          };

          storage = {
            filesystem_folder = lib.mkDefault "/var/lib/radicale/collections";
          };

          logging = {
            level = "info";
          };

          rights = {
            type = "from_file";
            file = builtins.toString (pkgs.writeText "radicale-rights" ''
              # Allow reading and writing principal collection (same as username)
              [principal]
              user: .+
              collection: {user}
              permissions: RW

              # Allow reading and writing calendars and address books that are direct
              # children of the principal collection
              [calendars]
              user: .+
              collection: {user}/[^/]+
              permissions: rw
            '');
          };
        };
      };
    };

    services.caddy.virtualHosts."radicale.neb.jakehillion.me" = {
      listenAddresses = [ "::1" config.custom.dns.nebula.ipv4 ];
      extraConfig = ''
        tls {
          ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
        }

        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    # Ensure storage directory exists (needed when overriding default path)
    systemd.tmpfiles.rules = [
      "d ${config.services.radicale.settings.storage.filesystem_folder} 0700 radicale radicale - -"
    ];
  };
}
