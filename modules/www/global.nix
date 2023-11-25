{ pkgs, lib, config, ... }:

let
  cfg = config.custom.www.global;
  locations = config.custom.locations.locations;
in
{
  options.custom.www.global = {
    enable = lib.mkEnableOption "global";
  };

  config = lib.mkIf cfg.enable {
    custom.www.www-repo.enable = true;

    users.users.caddy.extraGroups = [ "mastodon" ];

    services.caddy = {
      enable = true;

      virtualHosts = {
        "hillion.co.uk".extraConfig = ''
          handle /.well-known/* {
            respond /.well-known/matrix/server "{\"m.server\": \"matrix.hillion.co.uk:443\"}" 200
            respond 404
          }

          handle {
            redir https://blog.hillion.co.uk{uri}
          }
        '';
        "blog.hillion.co.uk".extraConfig = ''
          root * /var/www/blog.hillion.co.uk
          file_server
        '';
        "gitea.hillion.co.uk".extraConfig = ''
          reverse_proxy http://gitea.gitea.ts.hillion.co.uk:3000
        '';
        "homeassistant.hillion.co.uk".extraConfig = ''
          reverse_proxy http://homeassistant.homeassistant.ts.hillion.co.uk:8123
        '';
        "emby.hillion.co.uk".extraConfig = ''
          reverse_proxy http://plex.mediaserver.ts.hillion.co.uk:8096
        '';
        "matrix.hillion.co.uk".extraConfig = ''
          reverse_proxy http://${locations.services.matrix}:8008
        '';
        "unifi.hillion.co.uk".extraConfig = ''
          reverse_proxy https://unifi.unifi.ts.hillion.co.uk:8443 {
            transport http {
              tls_insecure_skip_verify
            }
          }
        '';
        "drone.hillion.co.uk".extraConfig = ''
          reverse_proxy http://vm.strangervm.ts.hillion.co.uk:18733
        '';
      };
    };
  };
}
