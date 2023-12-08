{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.unifi;
in
{
  options.custom.services.unifi = {
    enable = lib.mkEnableOption "unifi";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/unifi";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.unifi = {
      uid = config.ids.uids.unifi;
      isSystemUser = true;
      group = "unifi";
      description = "UniFi controller daemon user";
      home = "${cfg.dataDir}";
    };
    users.groups.unifi = {
      gid = config.ids.gids.unifi;
    };

    services.caddy = {
      enable = true;
      virtualHosts = {
        "unifi.hillion.co.uk".extraConfig = ''
          reverse_proxy https://localhost:8443 {
            transport http {
              tls_insecure_skip_verify
            }
          }
        '';
      };
    };

    virtualisation.oci-containers.containers = {
      "unifi" = {
        image = "lscr.io/linuxserver/unifi-controller:8.0.7-ls218";
        environment = {
          PUID = toString config.ids.uids.unifi;
          PGID = toString config.ids.gids.unifi;
          TZ = "Etc/UTC";
        };
        volumes = [ "${cfg.dataDir}:/config" ];
        ports = [
          "8080:8080"
          "8443:8443"
          "3478:3478/udp"
        ];
      };
    };
  };
}

