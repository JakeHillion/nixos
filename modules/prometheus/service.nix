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

      scrapeConfigs = [{
        job_name = "node";
        static_configs = [{
          targets = builtins.map (x: "${x}:9000") (builtins.attrNames (builtins.readDir ../../hosts));
        }];
      }];

      rules = [
        ''
          groups:
          - name: service alerting
            rules:
            - alert: ResilioSyncDown
              expr: node_systemd_unit_state{ name = 'resilio.service', state != 'active' } > 0
              for: 10m
              annotations:
                summary: "Resilio Sync systemd service is down"
                description: "The Resilio Sync systemd service is not active on instance {{ $labels.instance }}."
        ''
      ];
    };

    services.caddy = {
      enable = true;
      virtualHosts."prometheus.ts.hillion.co.uk" = {
        listenAddresses = [ config.custom.dns.tailscale.ipv4 config.custom.dns.tailscale.ipv6 ];
        extraConfig = ''
          reverse_proxy http://localhost:9090

          tls {
            ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
          }
        '';
      };
    };
    ### HACK: Allow Caddy to restart if it fails. This happens because Tailscale
    ### is too late at starting. Upstream nixos caddy does restart on failure
    ### but it's prevented on exit code 1. Set the exit code to 0 (non-failure)
    ### to override this.
    systemd.services.caddy = {
      requires = [ "tailscaled.service" ];
      after = [ "tailscaled.service" ];
      serviceConfig = {
        RestartPreventExitStatus = lib.mkForce 0;
      };
    };
  };
}
