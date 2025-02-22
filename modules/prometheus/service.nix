{ pkgs, lib, config, ... }:

let
  cfg = config.custom.services.prometheus;
in
{
  options.custom.services.prometheus = {
    enable = lib.mkEnableOption "prometheus-client";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;

      globalConfig = {
        scrape_interval = "15s";
      };
      retentionTime = "1y";

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets =
              let
                hosts = builtins.map
                  (
                    x: "${lib.concatStringsSep "." (lib.take 2 (lib.splitString "." x))}.neb.jakehillion.me"
                  )
                  (builtins.attrNames (builtins.readDir ../../hosts));
              in
              lib.lists.flatten (builtins.map (x: [ "${x}:9000" "${x}:9001" ]) hosts);
          }];
        }
      ];
    };

    services.caddy = {
      enable = true;
      virtualHosts."prometheus.neb.jakehillion.me" = {
        listenAddresses = [ config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          reverse_proxy http://localhost:9090

          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }
        '';
      };
    };
  };
}
