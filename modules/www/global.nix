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
    users.users.caddy.extraGroups = [ "mastodon" ];

    services.caddy = {
      enable = true;

      virtualHosts."hillion.co.uk".extraConfig = ''
        handle /.well-known/* {
          respond /.well-known/matrix/server "{\"m.server\": \"matrix.hillion.co.uk:443\"}" 200
          respond 404
        }

        handle {
          redir https://blog.hillion.co.uk{uri}
        }
      '';
      virtualHosts."blog.hillion.co.uk".extraConfig = ''
        root * /var/www/blog.hillion.co.uk
        file_server
      '';
      virtualHosts."gitea.hillion.co.uk".extraConfig = ''
        reverse_proxy http://gitea.gitea.ts.hillion.co.uk:3000
      '';
      virtualHosts."homeassistant.hillion.co.uk".extraConfig = ''
        reverse_proxy http://homeassistant.homeassistant.ts.hillion.co.uk:8123
      '';
      virtualHosts."emby.hillion.co.uk".extraConfig = ''
        reverse_proxy http://plex.mediaserver.ts.hillion.co.uk:8096
      '';
      virtualHosts."matrix.hillion.co.uk".extraConfig = ''
        reverse_proxy http://${locations.services.matrix}:8008
      '';
      virtualHosts."unifi.hillion.co.uk".extraConfig = ''
        reverse_proxy https://unifi.unifi.ts.hillion.co.uk:8443 {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
      virtualHosts."drone.hillion.co.uk".extraConfig = ''
        reverse_proxy http://vm.strangervm.ts.hillion.co.uk:18733
      '';
      virtualHosts."social.hillion.co.uk".extraConfig = ''
        handle_path /system/* {
          file_server * {
            root /var/lib/mastodon/public-system
          }
        }

        handle /api/v1/streaming/* {
          reverse_proxy  unix//run/mastodon-streaming/streaming.socket
        }
      
        route * {
          file_server * {
            root ${pkgs.mastodon}/public
            pass_thru
          }
          reverse_proxy * unix//run/mastodon-web/web.socket
        }

        handle_errors {
          root * ${pkgs.mastodon}/public
          rewrite 500.html
          file_server
        }

        encode gzip

        header /* {
          Strict-Transport-Security "max-age=31536000;"
        }
        header /emoji/* Cache-Control "public, max-age=31536000, immutable"
        header /packs/* Cache-Control "public, max-age=31536000, immutable"
        header /system/accounts/avatars/* Cache-Control "public, max-age=31536000, immutable"
        header /system/media_attachments/files/* Cache-Control "public, max-age=31536000, immutable"
      '';
    };
  };
}
