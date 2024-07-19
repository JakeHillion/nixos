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
      readOnly = true; # NixOS module only supports this directory
    };
  };

  config = lib.mkIf cfg.enable {
    # Fix dynamically allocated user and group ids
    users.users.unifi.uid = config.ids.uids.unifi;
    users.groups.unifi.gid = config.ids.gids.unifi;

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

    services.unifi = {
      enable = true;
      unifiPackage = pkgs.unifi8;
    };
  };
}

