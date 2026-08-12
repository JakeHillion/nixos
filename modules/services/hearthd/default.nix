{ config, pkgs, lib, ... }:

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

  # Portal dashboard server: serves /state and /template/<hash> for Portals,
  # pulling live light state from the colocated hearthd. Exposed on the IoT
  # vhost under /extra/portals/ (see caddy below).
  portalsPort = 8566;
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

          handle_path /extra/portals/* {
            reverse_proxy http://127.0.0.1:${toString portalsPort}
          }

          handle {
            reverse_proxy http://127.0.0.1:8565
          }
        '';
      };
    };

    systemd.services.hearthd-portals = {
      description = "hearthd portal dashboard server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "hearthd.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./portals/serve.py} ${./portals/template.json} --host 127.0.0.1 --port ${toString portalsPort} --hearthd http://127.0.0.1:8565";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;

        # Hardening: the server reads only its Nix-store template and talks to
        # the local hearthd over loopback, so lock everything else down.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
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
