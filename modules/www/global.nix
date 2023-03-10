{ pkgs, lib, config, ... }:

{
  imports = [
    ./www-repo.nix
  ];

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 443 ];
  };

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
    virtualHosts."ts.hillion.co.uk".extraConfig = ''
      reverse_proxy http://10.48.62.14:8080
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
      reverse_proxy http://vm.strangervm.ts.hillion.co.uk:8008
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
  };
}

