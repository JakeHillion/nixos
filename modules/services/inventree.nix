{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.inventree;
in
{
  options.custom.services.inventree = {
    enable = lib.mkEnableOption "inventree";

    path = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/inventree";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "inventree.neb.jakehillion.me";
    };

    hostPort = lib.mkOption {
      type = lib.types.port;
      default = 4864;
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.inventree.gid = config.ids.gids.inventree;
    users.users.inventree = {
      home = cfg.path;
      createHome = true;
      homeMode = "0750";

      isSystemUser = true;
      group = "inventree";
      uid = config.ids.uids.inventree;
    };
    users.users.caddy.extraGroups = [ "inventree" ];

    services.postgresql = {
      enable = true;
      enableTCPIP = true;

      ensureDatabases = [ "inventree" ];
      ensureUsers = [{
        name = "inventree";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }];
      authentication = "hostnossl inventree inventree 0.0.0.0 0.0.0.0 scram-sha-256";
    };

    services.caddy = {
      enable = true;
      virtualHosts.${cfg.domain} = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];

        # NOTE: Inventree recommends authing /media, but we will accept the Nebula bind for now.
        extraConfig = ''
          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }

          encode zstd gzip

          request_body {
            max_size 100MB
          }

          handle /static/* {
            root * ${cfg.path}/static
            file_server
          }

          handle /media/* {
            root * ${cfg.path}/media
            file_server
          }

          reverse_proxy http://localhost:${toString cfg.hostPort}
        '';
      };
    };

    # virtualisation.oci-containers.containers.inventree = {
    #   image = "inventree/inventree:${version}";

    #   ports = [ "${toString cfg.hostPort}:8000" ];
    #   extraOptions = [
    #     "--uidmap=0:${toString config.users.users.inventree.uid}:1"
    #     "--gidmap=0:${toString config.users.groups.inventree.gid}:1"
    #   ];
    #   volumes = [
    #     "${cfg.path}:/home/inventree/data"
    #     "/var/run/postgresql:/var/run/postgresql"
    #   ];
    #   environment = {
    #     INVENTREE_SITE_URL = "https://${cfg.domain}";

    #     INVENTREE_DEBUG = "False";
    #     INVENTREE_LOG_LEVEL = "WARNING";

    #     # Database setup
    #     INVENTREE_DB_ENGINE = "postgresql";
    #     INVENTREE_DB_NAME = "inventree";
    #     INVENTREE_DB_HOST = "10.88.0.1";
    #     INVENTREE_DB_PORT = "5432";

    #     INVENTREE_DB_USER = "inventree";
    #     INVENTREE_DB_PASSWORD = "inventree";

    #     # Web server
    #     INVENTREE_GUNICORN_TIMEOUT = "90";

    #     # Migrations
    #     INVENTREE_AUTO_UPDATE = "True";
    #   };
    # };
  };
}
