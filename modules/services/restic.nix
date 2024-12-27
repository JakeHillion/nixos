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

      type = with lib.types; attrsOf (submodule {
        options = {
          path = lib.mkOption {
            default = null;
            type = nullOr str;
          };
          passwordFile = lib.mkOption {
            default = null;
            type = nullOr str;
          };
          environmentFile = lib.mkOption {
            default = null;
            type = nullOr str;
          };

          forgetConfig = lib.mkOption {
            default = null;
            type = nullOr (submodule {
              options = {
                timerConfig = lib.mkOption {
                  type = attrs;
                };
                opts = lib.mkOption {
                  type = listOf str;
                };
              };
            });
          };

          clones = lib.mkOption {
            default = [ ];
            type = listOf (submodule {
              options = {
                timerConfig = lib.mkOption {
                  type = attrs;
                };
                repo = lib.mkOption {
                  type = str;
                };
              };
            });
          };
        };
      });

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

          clones = [
            {
              repo = "128G-wasabi";
              timerConfig = {
                OnBootSec = "30m";
                OnUnitInactiveSec = "60m";
                RandomizedDelaySec = "20m";
              };
            }
            {
              repo = "128G-backblaze";
              timerConfig = {
                OnBootSec = "30m";
                OnUnitInactiveSec = "60m";
                RandomizedDelaySec = "20m";
              };
            }
          ];
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

          clones = [
            {
              repo = "1.6T-wasabi";
              timerConfig = {
                OnBootSec = "30m";
                OnUnitInactiveSec = "60m";
                RandomizedDelaySec = "20m";
              };
            }
            {
              repo = "1.6T-backblaze";
              timerConfig = {
                OnBootSec = "30m";
                OnUnitInactiveSec = "60m";
                RandomizedDelaySec = "20m";
              };
            }
          ];
        };

        "128G-wasabi" = {
          environmentFile = config.age.secrets."restic/128G-wasabi.env".path;
        };
        "1.6T-wasabi" = {
          environmentFile = config.age.secrets."restic/1.6T-wasabi.env".path;
        };

        "128G-backblaze" = {
          environmentFile = config.age.secrets."restic/128G-backblaze.env".path;
        };
        "1.6T-backblaze" = {
          environmentFile = config.age.secrets."restic/1.6T-backblaze.env".path;
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
      "restic/128G-wasabi.env".file = ../../secrets/restic/128G-wasabi.env.age;
      "restic/128G-backblaze.env".file = ../../secrets/restic/128G-backblaze.env.age;

      "restic/1.6T.key" = {
        file = ../../secrets/restic/1.6T.age;
        owner = "restic";
        group = "restic";
      };
      "restic/1.6T-wasabi.env".file = ../../secrets/restic/1.6T-wasabi.env.age;
      "restic/1.6T-backblaze.env".file = ../../secrets/restic/1.6T-backblaze.env.age;
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
      virtualHosts."restic.neb.jakehillion.me".extraConfig = ''
        bind ${config.custom.dns.nebula.ipv4}
        tls {
          ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
        }

        reverse_proxy http://localhost:8000
      '';
    };

    systemd =
      let
        mkRepoInfo = repo_cfg: (if (repo_cfg.passwordFile != null) then {
          serviceConfig.LoadCredential = [
            "password_file:${repo_cfg.passwordFile}"
          ];
          environment = {
            RESTIC_REPOSITORY = repo_cfg.path;
            RESTIC_PASSWORD_FILE = "%d/password_file";
          };
        } else {
          serviceConfig.EnvironmentFile = repo_cfg.environmentFile;
        });

        mkForgetService = name: repo_cfg:
          if (repo_cfg.forgetConfig != null) then
            lib.mkMerge [
              {
                description = "Restic forget service for ${name}";

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
              }
              (mkRepoInfo repo_cfg)
            ] else { };
        mkForgetTimer = repo_cfg:
          if (repo_cfg.forgetConfig != null) then {
            wantedBy = [ "timers.target" ];
            timerConfig = repo_cfg.forgetConfig.timerConfig;
          } else { };

        mkCloneService = from_repo: clone_cfg: to_repo: {
          name = "restic-clone-${from_repo.name}-${to_repo.name}";
          value = lib.mkMerge [
            {
              description = "Restic copy from ${from_repo.name} to ${to_repo.name}";

              serviceConfig = {
                User = "restic";
                Group = "restic";

                LoadCredential = [
                  "from_password_file:${from_repo.cfg.passwordFile}"
                ];
              };

              environment = {
                RESTIC_FROM_PASSWORD_FILE = "%d/from_password_file";
              };

              script = ''
                set -xe

                ${pkgs.restic}/bin/restic copy \
                    --from-repo ${from_repo.cfg.path} \
                    --retry-lock 30m
              '';
            }
            (mkRepoInfo to_repo.cfg)
          ];
        };
        mkCloneTimer = from_repo: clone_cfg: to_repo: {
          name = "restic-clone-${from_repo.name}-${to_repo.name}";
          value = {
            wantedBy = [ "timers.target" ];
            timerConfig = clone_cfg.timerConfig;
          };
        };

        mapClones = fn: builtins.listToAttrs (lib.lists.flatten (lib.mapAttrsToList
          (
            from_repo_name: from_repo_cfg: (builtins.map
              (
                clone_cfg: (fn
                  { name = from_repo_name; cfg = from_repo_cfg; }
                  clone_cfg
                  { name = clone_cfg.repo; cfg = cfg.repos."${clone_cfg.repo}"; }
                )
              )
              from_repo_cfg.clones)
          )
          cfg.repos));

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
        }
        // lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetService name value)) cfg.repos
        // mapClones mkCloneService;

        timers = lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetTimer value)) cfg.repos
          // mapClones mkCloneTimer;
      };
  };
}
