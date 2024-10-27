{ config, pkgs, lib, ... }:

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

    repos = lib.mkOption {
      readOnly = true;

      default = {
        "128G" = {
          path = "${cfg.path}/128G";
          passwordFile = config.age.secrets."restic/128G.key".path;

          forgetConfig = {
            timerConfig = {
              OnCalendar = "02:30";
              RandomizedDelaySec = "1h";
            };
            opts = [
              "--keep-last 48"
              "--keep-within-hourly 7d"
              "--keep-within-daily 1m"
              "--keep-within-weekly 6m"
              "--keep-within-monthly 24m"
            ];
          };
        };

        "1.6T" = {
          path = "${cfg.path}/1.6T";
          passwordFile = config.age.secrets."restic/1.6T.key".path;

          forgetConfig = {
            timerConfig = {
              OnCalendar = "Wed, 02:30";
              RandomizedDelaySec = "4h";
            };
            opts = [
              "--keep-within-daily 14d"
              "--keep-within-weekly 2m"
              "--keep-within-monthly 18m"
            ];
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "restic/128G.key" = {
        file = ../../secrets/restic/128G.age;
        owner = "restic";
        group = "restic";
      };

      "restic/1.6T.key" = {
        file = ../../secrets/restic/1.6T.age;
        owner = "restic";
        group = "restic";
      };
    };

    services.restic.server = {
      enable = true;
      appendOnly = true;
      extraFlags = [ "--no-auth" ];
      dataDir = cfg.path;
      listenAddress = "127.0.0.1:8000"; # TODO: can this be a Unix socket?
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

    systemd =
      let
        mkRepoInfo = repo_cfg: {
          serviceConfig.LoadCredential = [
            "password_file:${repo_cfg.passwordFile}"
          ];
          environment = {
            RESTIC_REPOSITORY = repo_cfg.path;
            RESTIC_PASSWORD_FILE = "%d/password_file";
          };
        };

        mkForgetService = name: repo_cfg: ({
          description = "Restic remote copy service ${name}";

          serviceConfig = {
            User = "restic";
            Group = "restic";
          };

          script = ''
            set -xe

            ${pkgs.restic}/bin/restic forget ${lib.strings.concatStringsSep " " repo_cfg.forgetConfig.opts} \
              --prune \
              --retry-lock 30m
          '';
        } // (mkRepoInfo repo_cfg));
        mkForgetTimer = repo_cfg: {
          wantedBy = [ "timers.target" ];
          timerConfig = repo_cfg.forgetConfig.timerConfig;
        };

      in
      {
        services = {
          caddy = {
            ### HACK: Allow Caddy to restart if it fails. This happens because Tailscale
            ### is too late at starting. Upstream nixos caddy does restart on failure
            ### but it's prevented on exit code 1. Set the exit code to 0 (non-failure)
            ### to override this.
            requires = [ "tailscaled.service" ];
            after = [ "tailscaled.service" ];
            serviceConfig = {
              RestartPreventExitStatus = lib.mkForce 0;
            };
          };
        } // lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetService name value)) cfg.repos;

        timers = lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetTimer value)) cfg.repos;
      };
  };
}
