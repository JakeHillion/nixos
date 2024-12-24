{ pkgs, lib, config, ... }:

let
  cfg = config.custom.www.home;
  locations = config.custom.locations.locations;
in
{
  options.custom.www.home = {
    enable = lib.mkEnableOption "home";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      virtualHosts = {
        "homeassistant.home.hillion.co.uk".extraConfig = ''
          bind 10.64.50.25
          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }
          reverse_proxy http://${locations.services.homeassistant}:8123
        '';
      };
    };
  };
}
