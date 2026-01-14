{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.matrix;
in
{
  options.custom.services.matrix = {
    enable = lib.mkEnableOption "matrix";

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
    };

    heisenbridge = lib.mkOption {
      default = true;
      type = lib.types.bool;
    };

    mautrix_discord = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = "Load mautrix-discord bridge registration";
    };

    mautrix_meta = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = "Load mautrix-meta bridge registration";
    };
  };

  config = lib.mkIf cfg.enable {
    services.matrix-synapse.dataDir = lib.mkIf config.custom.impermanence.enable "${config.custom.impermanence.base}/system/var/lib/matrix-synapse";

    age.secrets = {
      "backups/matrix/restic/mig29" = lib.mkIf cfg.backup {
        file = ../../../secrets/restic/mig29.age;
      };

      "matrix/matrix.hillion.co.uk/macaroon_secret_key" = {
        file = ./matrix.hillion.co.uk/macaroon_secret_key.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/email" = {
        file = ./matrix.hillion.co.uk/email.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/registration_shared_secret" = {
        file = ./matrix.hillion.co.uk/registration_shared_secret.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/syncv3_secret" = {
        file = ./matrix.hillion.co.uk/syncv3_secret.age;
      };

      "mautrix-discord/registration.yaml" = lib.mkIf cfg.mautrix_discord {
        file = ../mautrix-discord/registration.yaml.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "mautrix-meta/registration.yaml" = lib.mkIf cfg.mautrix_meta {
        file = ../mautrix-meta/registration.yaml.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };
    };

    services = {
      postgresqlBackup = lib.mkIf cfg.backup {
        enable = true;
        compression = "none"; # for better diffing
        databases = [ "matrix-synapse" ];
      };

      postgresql = {
        enable = true;
        initialScript = pkgs.writeText "synapse-init.sql" ''
          CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
          CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
            TEMPLATE template0
            LC_COLLATE = "C"
            LC_CTYPE = "C";
        '';
      };

      restic.backups."matrix" = lib.mkIf cfg.backup {
        user = "root";
        timerConfig = {
          OnCalendar = "03:00";
          RandomizedDelaySec = "60m";
        };
        repository = "rest:https://restic.${config.ogygia.domain}/mig29";
        passwordFile = config.age.secrets."backups/matrix/restic/mig29".path;
        paths = [
          "${config.services.postgresqlBackup.location}/matrix-synapse.sql"
          config.services.matrix-synapse.dataDir
        ];
      };

      matrix-synapse = {
        enable = true;

        extraConfigFiles = [
          config.age.secrets."matrix/matrix.hillion.co.uk/macaroon_secret_key".path
          config.age.secrets."matrix/matrix.hillion.co.uk/email".path
        ];

        settings = {
          registration_shared_secret_path = config.age.secrets."matrix/matrix.hillion.co.uk/registration_shared_secret".path;

          server_name = "hillion.co.uk";
          public_baseurl = "https://matrix.hillion.co.uk/";
          listeners = [
            {
              port = 8008;
              tls = false;
              type = "http";
              x_forwarded = true;
              bind_addresses = [
                "::1"
                config.custom.dns.nebula.ipv4
              ];
              resources = [
                {
                  names = [ "client" "federation" ];
                  compress = false;
                }
              ];
            }
          ];
          database = {
            name = "psycopg2";
            args = {
              database = "matrix-synapse";
              user = "matrix-synapse";
              password = "synapse";
              host = "127.0.0.1";
              cp_min = 5;
              cp_max = 10;
            };
          };
          enable_registration = true;
          registrations_require_3pid = [ "email" ];
          allowed_local_3pids = [
            {
              medium = "email";
              pattern = "^[^@]+@hillion\.co\.uk$";
            }
          ];
          suppress_key_server_warning = true;
          dynamic_thumbnails = true;
          app_service_config_files =
            (lib.optional cfg.heisenbridge "/var/lib/heisenbridge/registration.yml") ++
            (lib.optional cfg.mautrix_discord config.age.secrets."mautrix-discord/registration.yaml".path) ++
            (lib.optional cfg.mautrix_meta config.age.secrets."mautrix-meta/registration.yaml".path);
        };
      };

      heisenbridge = lib.mkIf cfg.heisenbridge {
        enable = true;
        owner = "@jake:hillion.co.uk";
        homeserver = "https://matrix.hillion.co.uk";
      };
    };

    systemd.services = {
      heisenbridge = lib.mkIf cfg.heisenbridge {
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 15;
        };
      };
    };
  };
}
