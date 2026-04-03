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
      "backups/radicale/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../secrets/restic/mig29.age;
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
        repository = "rest:https://restic.${config.ogygia.domain}/mig29";
        passwordFile = config.age.secrets."backups/radicale/restic/mig29".path;
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
            filesystem_folder =
              if config.custom.impermanence.enable
              then "${config.custom.impermanence.base}/services/radicale/collections"
              else "/var/lib/radicale/collections";
          };

          logging = {
            level = "info";
          };

          rights = {
            type = "from_file";
            file = builtins.toString (pkgs.writeText "radicale-rights" ''
              # Allow personal-agent to read specific jake calendars
              [personal-agent-jake-calendars]
              user: personal-agent
              collection: jake/(69F72067-3C92-40C4-99FB-911D27FCD8E9|94E7F50D-CDFC-41B6-BAC7-E94EBA42AF5D)
              permissions: r

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

    custom.www.nebula = {
      enable = true;
      virtualHosts."radicale.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    # Ensure storage directory exists (needed when overriding default path)
    systemd.tmpfiles.rules = [
      "d ${config.services.radicale.settings.storage.filesystem_folder} 0700 radicale radicale - -"
    ];
  };
}
