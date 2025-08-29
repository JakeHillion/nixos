{ config, lib, pkgs, ... }:

let
  cfg = config.custom.www.nebula;
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
      '';

      virtualHosts = lib.attrsets.mapAttrs
        (name: value: (value // {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
            }
          '' + value.extraConfig;
        }))
        cfg.virtualHosts;
    };
  };
}
