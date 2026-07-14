{ config, lib, pkgs, ... }:

let
  cfg = config.custom.www.nebula;
  locations = config.custom.locations.locations;

  # The ACME DNS API host - use the first authoritative_dns host
  acmeApiHost =
    let
      authDns = locations.services.authoritative_dns;
    in
    if builtins.isList authDns then builtins.head authDns else authDns;
in
{
  options.custom.www.nebula = {
    enable = lib.mkEnableOption "caddy-nebula";
    virtualHosts = lib.mkOption {
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      globalConfig = ''
        servers {
        	trusted_proxies static 172.20.0.0/24
        }
        email acme@jakehillion.me
      '';

      virtualHosts = lib.attrsets.mapAttrs
        (name: value: (value // {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              dns jakehillion {
                api_endpoint http://${acmeApiHost}:8553
              }
            }
          '' + value.extraConfig;
        }))
        cfg.virtualHosts;
    };

    systemd.services.caddy = {
      after = [ "nebula-online@jakehillion.service" ];
      requires = [ "nebula-online@jakehillion.service" ];
    };
  };
}
