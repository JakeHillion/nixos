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
    # Reaching the acme-dns-api (on the authoritative_dns host) for DNS-01
    # challenges is the one Nebula path every internal-TLS host needs. Grant it
    # here, at the point of use, so access follows the service rather than
    # riding on the broad legacy-full-access group — which lets restrictive and
    # future hosts drop legacy-full-access without losing certs.
    ogygia.nebula.groups = [ "acme-dns-client" ];

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
      after = [ "nebula-online@ogygia.service" ];
      requires = [ "nebula-online@ogygia.service" ];
    };
  };
}
