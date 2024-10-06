{ pkgs, lib, config, ... }:

let
  cfg = config.custom.www.iot;
  locations = config.custom.locations.locations;
in
{
  options.custom.www.iot = {
    enable = lib.mkEnableOption "iot";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      package = pkgs.unstable.caddy;

      virtualHosts = {
        "homeassistant.iot.hillion.co.uk".extraConfig = ''
          bind 10.239.19.5
          tls {
            ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
          }

          @blocked not remote_ip 10.239.19.4
          respond @blocked "<h1>Access Denied</h1>" 403

          reverse_proxy http://${locations.services.homeassistant}:8123
        '';
      };
    };
  };
}
