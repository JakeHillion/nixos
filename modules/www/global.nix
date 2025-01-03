{ pkgs, lib, config, nixpkgs-unstable, ... }:

let
  cfg = config.custom.www.global;
  locations = config.custom.locations.locations;
in
{
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/web-servers/caddy/default.nix" ];
  disabledModules = [ "services/web-servers/caddy/default.nix" ];

  options.custom.www.global = {
    enable = lib.mkEnableOption "global";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = (
      let
        mkSecret = domain: {
          name = "caddy/${domain}.pem";
          value = {
            file = ../../secrets/certs/${domain}.pem.age;
            owner = config.services.caddy.user;
            group = config.services.caddy.group;
          };
        };
      in
      builtins.listToAttrs (builtins.map mkSecret [
        "hillion.co.uk"
        "blog.hillion.co.uk"
        "gitea.hillion.co.uk"
        "homeassistant.hillion.co.uk"
        "links.hillion.co.uk"
      ])
    ) // {
      "cloudflare/zone_keys.env" = {
        file = ../../secrets/cloudflare/zone_keys.env.age;
        owner = config.services.caddy.user;
        group = config.services.caddy.group;
      };
    };

    custom.www.www-repo.enable = true;

    services.caddy = {
      enable = true;

      environmentFile = config.age.secrets."cloudflare/zone_keys.env".path;

      globalConfig = ''
        email acme@hillion.co.uk
      '';

      virtualHosts = {
        ## Cloudflare proxied sites
        "hillion.co.uk".extraConfig = ''
          tls ${./certs/hillion.co.uk.pem} ${config.age.secrets."caddy/hillion.co.uk.pem".path}
          handle /.well-known/* {
            header /.well-known/matrix/* Content-Type application/json
            header /.well-known/matrix/* Access-Control-Allow-Origin *

            respond /.well-known/matrix/server "{\"m.server\": \"matrix.hillion.co.uk:443\"}" 200
            respond /.well-known/matrix/client `${builtins.toJSON {
              "m.homeserver" = { "base_url" = "https://matrix.hillion.co.uk"; };
            }}` 200

            respond 404
          }

          handle {
            redir https://blog.hillion.co.uk{uri}
          }
        '';
        "blog.hillion.co.uk".extraConfig = ''
          tls ${./certs/blog.hillion.co.uk.pem} ${config.age.secrets."caddy/blog.hillion.co.uk.pem".path}
          root * /var/www/blog.hillion.co.uk
          file_server
        '';
        "homeassistant.hillion.co.uk".extraConfig = ''
          tls ${./certs/homeassistant.hillion.co.uk.pem} ${config.age.secrets."caddy/homeassistant.hillion.co.uk.pem".path}
          reverse_proxy http://${locations.services.homeassistant}:8123
        '';
        "gitea.hillion.co.uk".extraConfig = ''
          tls ${./certs/gitea.hillion.co.uk.pem} ${config.age.secrets."caddy/gitea.hillion.co.uk.pem".path}
          reverse_proxy http://${locations.services.gitea}:3000
        '';
        "links.hillion.co.uk".extraConfig = ''
          tls ${./certs/links.hillion.co.uk.pem} ${config.age.secrets."caddy/links.hillion.co.uk.pem".path}
          redir https://matrix.to/#/@jake:hillion.co.uk
        '';

        ## ACME sites
        "matrix.hillion.co.uk".extraConfig = ''
          tls {
            dns cloudflare {
              zone_token {env.CF_ZONE_TOKEN}
              api_token {env.CF_API_TOKEN_HILLION_CO_UK}
            }
          }
          reverse_proxy /_matrix/* http://${locations.services.matrix}:8008
          reverse_proxy /_synapse/client/* http://${locations.services.matrix}:8008
        '';
      };
    };
  };
}
