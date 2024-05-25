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
  };

  config = lib.mkIf cfg.enable {
    custom = {
      backups.matrix.enable = cfg.backup;
    };

    age.secrets = {
      "matrix/matrix.hillion.co.uk/macaroon_secret_key" = {
        file = ../../secrets/matrix/matrix.hillion.co.uk/macaroon_secret_key.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/email" = {
        file = ../../secrets/matrix/matrix.hillion.co.uk/email.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/registration_shared_secret" = {
        file = ../../secrets/matrix/matrix.hillion.co.uk/registration_shared_secret.age;
        owner = "matrix-synapse";
        group = "matrix-synapse";
      };

      "matrix/matrix.hillion.co.uk/syncv3_secret" = {
        file = ../../secrets/matrix/matrix.hillion.co.uk/syncv3_secret.age;
      };
    };

    services = {
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
                config.custom.dns.tailscale.ipv4
                config.custom.dns.tailscale.ipv6
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
          app_service_config_files = lib.mkIf cfg.heisenbridge [
            "/var/lib/heisenbridge/registration.yml"
          ];
        };
      };

      matrix-sliding-sync = {
        enable = true;
        environmentFile = config.age.secrets."matrix/matrix.hillion.co.uk/syncv3_secret".path;
        settings = {
          SYNCV3_SERVER = "https://matrix.hillion.co.uk";
          SYNCV3_BINDADDR = "[::]:8009";
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
