{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.mautrix_meta;
in
{
  options.custom.services.mautrix_meta = {
    enable = lib.mkEnableOption "mautrix-meta bridge";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [
      "olm-3.2.16"
    ];

    age.secrets = {
      "mautrix-meta/registration.yaml" = {
        file = ./registration.yaml.age;
        owner = "mautrix-meta-facebook";
        group = "mautrix-meta-facebook";
      };
      "mautrix-meta/environment" = {
        file = ./environment.age;
        owner = "mautrix-meta-facebook";
        group = "mautrix-meta-facebook";
      };
      "backups/mautrix-meta/restic/mig29" = {
        file = ../../../secrets/restic/mig29.age;
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "mautrix-meta-facebook" ];
      ensureUsers = [{
        name = "mautrix-meta-facebook";
        ensureDBOwnership = true;
      }];
    };

    services.postgresqlBackup = {
      enable = true;
      compression = "none";
      databases = [ "mautrix-meta-facebook" ];
    };

    services.restic.backups."mautrix-meta" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:35";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/mautrix-meta/restic/mig29".path;
      paths = [
        "${config.services.postgresqlBackup.location}/mautrix-meta-facebook.sql"
        "/var/lib/mautrix-meta-facebook"
      ];
    };

    services.mautrix-meta.instances.facebook = {
      enable = true;
      registerToSynapse = false;
      environmentFile = config.age.secrets."mautrix-meta/environment".path;

      settings = {
        homeserver = {
          domain = "hillion.co.uk";
          address = "https://matrix.hillion.co.uk";
        };
        appservice = {
          hostname = "0.0.0.0";
          port = 29321;
          address = "http://warlock.cx.${config.ogygia.domain}:29321";
          database = {
            type = "postgres";
            uri = "postgres:///mautrix-meta-facebook?host=/run/postgresql";
          };
          as_token = "$AS_TOKEN";
          hs_token = "$HS_TOKEN";
        };
        network.mode = "facebook";
        bridge.permissions."@jake:hillion.co.uk" = "admin";
      };
    };

    systemd.services.mautrix-meta-facebook = {
      after = [ "postgresql-setup.service" ];
      requires = [ "postgresql-setup.service" ];
    };
  };
}
