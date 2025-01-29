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
      virtualHosts = lib.attrsets.mapAttrs
        (name: value: (value // {
          listenAddresses = [ config.custom.dns.nebula.ipv4 ];
          extraConfig = ''
            tls {
              ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
            }
          '' + value.extraConfig;
        }))
        cfg.virtualHosts;
    };
  };
}
