{ config, pkgs, lib, ... }:

{
  config.custom.backups.matrix.enable = true;

  ## Matrix (matrix.hillion.co.uk)
  config.age.secrets."matrix/matrix.hillion.co.uk/macaroon_secret_key" = {
    file = ../../secrets/matrix/matrix.hillion.co.uk/macaroon_secret_key.age;
    owner = "matrix-synapse";
    group = "matrix-synapse";
  };
  config.age.secrets."matrix/matrix.hillion.co.uk/email" = {
    file = ../../secrets/matrix/matrix.hillion.co.uk/email.age;
    owner = "matrix-synapse";
    group = "matrix-synapse";
  };

  config.services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "synapse-init.sql" ''
      CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
      CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
        TEMPLATE template0
        LC_COLLATE = "C"
        LC_CTYPE = "C";
    '';
  };

  config.services.matrix-synapse = {
    enable = true;

    extraConfigFiles = [
      config.age.secrets."matrix/matrix.hillion.co.uk/macaroon_secret_key".path
      config.age.secrets."matrix/matrix.hillion.co.uk/email".path
    ];

    settings = {
      server_name = "hillion.co.uk";
      public_baseurl = "https://matrix.hillion.co.uk/";
      listeners = [
        {
          port = 8008;
          tls = false;
          type = "http";
          x_forwarded = true;
          bind_addresses = [ "::1" ];
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
      app_service_config_files = [
        "/var/lib/heisenbridge/registration.yml"
      ];
    };
  };

  config.services.heisenbridge = {
    enable = true;
    owner = "@jake:hillion.co.uk";
    homeserver = "https://matrix.hillion.co.uk";
  };
}
