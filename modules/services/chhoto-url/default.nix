{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.chhoto-url;

  port = 4567;
  backupDir = "/run/restic-backups-chhoto-url";
in
{
  options.custom.services.chhoto-url = {
    enable = lib.mkEnableOption "chhoto-url";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "jhlink.uk";
      description = "Public domain the short links are served from";
    };

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "chhoto-url/environment".rekeyFile = ./environment.age;

      "backups/chhoto-url/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../../secrets/restic/mig29.age;
      };
    };

    users.users.chhoto-url = {
      uid = config.ids.uids.chhoto-url;
      isSystemUser = true;
      group = "chhoto-url";
    };
    users.groups.chhoto-url = {
      gid = config.ids.gids.chhoto-url;
    };

    systemd.services.chhoto-url.serviceConfig.DynamicUser = lib.mkForce false;

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable
      [ "/var/lib/chhoto-url" ];

    services.chhoto-url = {
      enable = true;
      environmentFiles = [ config.age.secrets."chhoto-url/environment".path ];

      settings = {
        inherit port;
        listen_address = "127.0.0.1";
        site_url = "https://${cfg.domain}";

        hash_algorithm = "Argon2";
        redirect_method = "TEMPORARY";

        slug_style = "UID";
        slug_length = 6;
        try_longer_slug = true;

        use_wal_mode = true;
      };
    };

    # Only the redirects are public. The admin UI and API are reachable over
    # Nebula alone.
    services.caddy = {
      enable = true;
      virtualHosts.${cfg.domain}.extraConfig = ''
        @public {
          method GET HEAD
          path_regexp ^/([^/]+|(assets|static)/.+)$
        }
        handle @public {
          reverse_proxy http://127.0.0.1:${toString port}
        }
        handle {
          respond 404
        }
      '';
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."jhlink.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString port}
      '';
    };

    services.restic.backups."chhoto-url" = lib.mkIf cfg.backup {
      user = "root";
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/chhoto-url/restic/mig29".path;
      backupPrepareCommand = ''
        ${lib.getExe pkgs.sqlite} ${config.services.chhoto-url.settings.db_url} ".backup '${backupDir}/urls.sqlite'"
      '';
      paths = [ "${backupDir}/urls.sqlite" ];
    };
  };
}
