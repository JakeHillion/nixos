{ config, lib, ... }:

let
  cfg = config.custom.services.hearthd;

  acmeApiHost =
    let
      authDns = config.custom.locations.locations.services.authoritative_dns;
    in
    if builtins.isList authDns then builtins.head authDns else authDns;

  # IoT clients permitted to reach the hearthd vhost.
  hearthdAllowedClients = [
    "10.239.19.16" # bedroom-portal
  ];
in
{
  options.custom.services.hearthd = {
    enable = lib.mkEnableOption "hearthd";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."hearthd/locations.toml".file = ./locations.toml.age;
    age.secrets."hearthd/mqtt.toml".file = ./mqtt.toml.age;

    # The caddy vhost below solves DNS-01 challenges against the acme-dns-api on
    # ${acmeApiHost}:8553 over Nebula. Grant that path at the point of use so it
    # doesn't depend on the broad legacy-full-access group (see modules/www/nebula.nix).
    ogygia.nebula.groups = [ "acme-dns-client" ];

    custom.www.nebula = {
      enable = true;
      virtualHosts."hearthd.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://127.0.0.1:8565
      '';
    };

    services.caddy = {
      enable = true;

      virtualHosts."hearthd.iot.home.jakehillion.me" = {
        listenAddresses = [ "10.239.19.8" ];
        extraConfig = ''
          tls {
            dns jakehillion {
              api_endpoint http://${acmeApiHost}:8553
            }
          }

          @blocked not remote_ip ${lib.concatStringsSep " " hearthdAllowedClients}
          respond @blocked "<h1>Access Denied</h1>" 403

          reverse_proxy http://127.0.0.1:8565
        '';
      };
    };

    services.hearthd = {
      enable = true;

      secretConfigs = with config.age; [
        secrets."hearthd/locations.toml".path
        secrets."hearthd/mqtt.toml".path
      ];
      config = {
        logging = {
          level = "info";
          overrides = {
            "hearthd" = "debug";
          };
        };

        locations.default = "home";

        http = {
          listen = "127.0.0.1";
          port = 8565;
        };

        integrations.mqtt = {
          broker = "mqtt.home.${config.ogygia.domain}";
          port = 1883;
          client_id = "hearthd";
          discovery_prefix = "homeassistant";
          username = "hearthd";
        };
      };
    };
  };
}
