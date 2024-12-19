{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.immich;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "immich";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      virtualHosts."immich.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          reverse_proxy http://localhost:${toString config.services.immich.port}

          tls {
            ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
          }
        '';
      };
    };

    users.users.immich.uid = config.ids.uids.immich;
    users.groups.immich.gid = config.ids.gids.immich;

    services.immich = {
      enable = true;
    };
  };
}
