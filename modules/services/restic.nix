{ config, lib, ... }:

let
  cfg = config.custom.services.restic;
in
{
  options.custom.services.restic = {
    enable = lib.mkEnableOption "restic http server";

    path = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/restic";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."restic/128G.key" = {
      file = ../../secrets/restic/128G.age;
      owner = "restic";
      group = "restic";
    };
    age.secrets."restic/1.6T.key" = {
      file = ../../secrets/restic/1.6T.age;
      owner = "restic";
      group = "restic";
    };

    services.restic = {
      server = {
        enable = true;
        appendOnly = true;
        extraFlags = [ "--no-auth" ];
        dataDir = cfg.path;
        listenAddress = "127.0.0.1:8000"; # TODO: can this be a Unix socket?
      };

      backups = {
        "prune-128G" = {
          repository = "${cfg.path}/128G";
          user = "restic";
          passwordFile = config.age.secrets."restic/128G.key".path;

          timerConfig = {
            Persistent = true;
            OnCalendar = "02:30";
            RandomizedDelaySec = "1h";
          };

          pruneOpts = [
            "--keep-last 48"
            "--keep-within-hourly 7d"
            "--keep-within-daily 1m"
            "--keep-within-weekly 6m"
            "--keep-within-monthly 24m"
          ];
        };
        "prune-1.6T" = {
          repository = "${cfg.path}/1.6T";
          user = "restic";
          passwordFile = config.age.secrets."restic/1.6T.key".path;

          timerConfig = {
            Persistent = true;
            OnCalendar = "Wed, 02:30";
            RandomizedDelaySec = "4h";
          };

          pruneOpts = [
            "--keep-within-daily 14d"
            "--keep-within-weekly 2m"
            "--keep-within-monthly 18m"
          ];
        };
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts."restic.ts.hillion.co.uk".extraConfig = ''
        bind ${config.custom.dns.tailscale.ipv4} ${config.custom.dns.tailscale.ipv6}
        tls {
          ca https://ca.ts.hillion.co.uk:8443/acme/acme/directory
        }

        reverse_proxy http://localhost:8000
      '';
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
