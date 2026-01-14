{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.mautrix_discord;
in
{
  options.custom.services.mautrix_discord = {
    enable = lib.mkEnableOption "mautrix-discord bridge";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [
      "olm-3.2.16"
    ];

    services.mautrix-discord.dataDir = lib.mkIf config.custom.impermanence.enable
      "${config.custom.impermanence.base}/services/mautrix-discord";

    age.secrets = {
      "mautrix-discord/registration.yaml" = {
        file = ./registration.yaml.age;
        owner = "mautrix-discord";
        group = "mautrix-discord";
      };
      "mautrix-discord/environment" = {
        file = ./environment.age;
        owner = "mautrix-discord";
        group = "mautrix-discord";
      };
      "backups/mautrix-discord/restic/mig29" = {
        file = ../../../secrets/restic/mig29.age;
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "mautrix-discord" ];
      ensureUsers = [{
        name = "mautrix-discord";
        ensureDBOwnership = true;
      }];
    };

    services.postgresqlBackup = {
      enable = true;
      compression = "none";
      databases = [ "mautrix-discord" ];
    };

    services.restic.backups."mautrix-discord" = {
      user = "root";
      timerConfig = {
        OnCalendar = "03:30";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/mautrix-discord/restic/mig29".path;
      paths = [
        "${config.services.postgresqlBackup.location}/mautrix-discord.sql"
        config.services.mautrix-discord.dataDir
      ];
    };

    services.mautrix-discord = {
      enable = true;
      registerToSynapse = false;
      environmentFile = config.age.secrets."mautrix-discord/environment".path;

      settings = {
        homeserver = {
          domain = "hillion.co.uk";
          address = "https://matrix.hillion.co.uk";
        };
        appservice = {
          hostname = "0.0.0.0";
          port = 29334;
          address = "http://warlock.cx.${config.ogygia.domain}:29334";
          database = {
            type = "postgres";
            uri = "postgres:///mautrix-discord?host=/run/postgresql";
          };
          as_token = "$AS_TOKEN";
          hs_token = "$HS_TOKEN";
          bot.username = "discordbot";
        };
        bridge.permissions."@jake:hillion.co.uk" = "admin";
      };
    };

    systemd.services.mautrix-discord = {
      after = [ "postgresql-setup.service" ];
      requires = [ "postgresql-setup.service" ];
    };
  };
}
