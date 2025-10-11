{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.attic;
in
{
  options.custom.services.attic = {
    enable = lib.mkEnableOption "attic";

    port = lib.mkOption {
      type = lib.types.port;
      default = 26284;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."attic/environment" = {
      file = ../../secrets/attic/environment.age;
    };

    users.users.atticd = {
      isSystemUser = true;
      group = "atticd";
      uid = config.ids.uids.atticd;
    };

    users.groups.atticd = {
      gid = config.ids.gids.atticd;
    };

    systemd.services.atticd.serviceConfig = {
      DynamicUser = lib.mkForce false;
    };

    services = {
      caddy = {
        enable = true;

        # attic-client rejects my self-signed CA. Use http for now as it's over nebula anyway.
        virtualHosts."http://attic.${config.ogygia.domain}" = {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            reverse_proxy http://localhost:${toString cfg.port}
          '';
        };
      };

      postgresql = {
        enable = true;
        initialScript = pkgs.writeText "attic-init.sql" ''
          CREATE ROLE "${config.services.atticd.user}" WITH LOGIN;
          CREATE DATABASE "attic" WITH OWNER "${config.services.atticd.user}" ENCODING "utf8";
        '';
      };

      atticd = {
        enable = true;
        user = "atticd";
        group = "atticd";
        environmentFile = config.age.secrets."attic/environment".path;

        settings = {
          listen = "127.0.0.1:${toString cfg.port}";

          allowed-hosts = [ "attic.${config.ogygia.domain}" ];
          api-endpoint = "http://attic.${config.ogygia.domain}/";

          database.url = "postgresql:///attic?host=/run/postgresql&user=atticd";

          storage = {
            type = "local";
            path = "/practical-defiant-coffee/attic";
          };
        };
      };
    };
  };
}
