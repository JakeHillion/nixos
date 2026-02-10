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

          packSize = lib.mkOption {
            default = null;
            type = lib.types.nullOr lib.types.int;
            description = "Pack size for restic operations. If null, no pack size argument is added.";
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
                maxSize = lib.mkOption {
                  default = null;
                  type = nullOr int;
                  description = "Max repo size in bytes. Oldest eligible snapshots forgotten when exceeded.";
                };
                minAgeDays = lib.mkOption {
                  default = 180;
                  type = int;
                  description = "Minimum snapshot age in days before eligible for size-based removal.";
                };
                repackSmall = lib.mkOption {
                  default = true;
                  type = bool;
                  description = "Repack small packs during prune. Disable for deep archive repos.";
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
        "mig29" = {
          path = "${cfg.path}/mig29";
          passwordFile = config.age.secrets."restic/mig29.key".path;
          packSize = 16;

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
              repo = "b52";
              timerConfig = {
                OnBootSec = "30m";
                OnUnitInactiveSec = "60m";
                RandomizedDelaySec = "20m";
              };
            }
            {
              repo = "aws-eu-central-2";
              # delibarately rare uploads to makes packs more likely to be full
              # as we can't repack on this data storage. timed to suit the
              # cutoff for the deep archive move.
              timerConfig = {
                OnCalendar = "23:00 UTC";
                RandomizedDelaySec = "30m";
                Persistent = true;
              };
            }
            {
              repo = "aws-us-east-1";
              # delibarately rare uploads to makes packs more likely to be full
              # as we can't repack on this data storage. timed to suit the
              # cutoff for the deep archive move.
              timerConfig = {
                OnCalendar = "23:00 UTC";
                RandomizedDelaySec = "30m";
                Persistent = true;
              };
            }
          ];
        };

        "b52" = {
          path = "${cfg.path}/b52";
          passwordFile = config.age.secrets."restic/b52.key".path;
          packSize = 64;

          forgetConfig = {
            timerConfig = {
              OnCalendar = "Wed, 02:30";
              RandomizedDelaySec = "4h";
            };
            opts = [
              "--keep-within-daily 14d"
              "--keep-within-weekly 2m"
              "--keep-monthly unlimited"
            ];
            maxSize = 2 * 1024 * 1024 * 1024 * 1024; # 2 TiB
          };

          clones = [
            {
              repo = "aws-eu-central-2";
              timerConfig = {
                OnUnitInactiveSec = "24h";
                RandomizedDelaySec = "2h";
                Persistent = true;
              };
            }
            {
              repo = "aws-us-east-1";
              timerConfig = {
                OnUnitInactiveSec = "24h";
                RandomizedDelaySec = "2h";
                Persistent = true;
              };
            }
          ];
        };

        "aws-eu-central-2" = {
          environmentFile = config.age.secrets."restic/aws-eu-central-2.env".path;
          packSize = 128;
        };
        "aws-us-east-1" = {
          environmentFile = config.age.secrets."restic/aws-us-east-1.env".path;
          packSize = 128;

          forgetConfig = {
            timerConfig = {
              OnCalendar = "Sun, 04:00 UTC";
              RandomizedDelaySec = "2h";
              Persistent = true;
            };
            opts = [
              "--keep-within-daily 31d"
              "--keep-within-weekly 16w"
              "--keep-monthly unlimited"
            ];
            maxSize = 5 * 1024 * 1024 * 1024 * 1024; # 5 TiB
            minAgeDays = 180;
            repackSmall = false; # deep archive: cannot repack
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "restic/mig29.key" = {
        file = ../../../secrets/restic/mig29.age;
        owner = "restic";
        group = "restic";
      };

      "restic/b52.key" = {
        file = ../../../secrets/restic/b52.age;
        owner = "restic";
        group = "restic";
      };

      "restic/aws-eu-central-2.env".file = ./aws-eu-central-2.env.age;
      "restic/aws-us-east-1.env".file = ./aws-us-east-1.env.age;
    };

    services.restic.server = {
      enable = true;
      appendOnly = true;
      extraFlags = [ "--no-auth" ];
      dataDir = cfg.path;
      listenAddress = "127.0.0.1:8000"; # TODO: can this be a Unix socket?
    };

    custom.www.nebula = {
      enable = true;
      virtualHosts."restic.${config.ogygia.domain}".extraConfig = ''
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
            let
              fc = repo_cfg.forgetConfig;
            in
            lib.mkMerge [
              {
                description = "Restic forget service for ${name}";

                serviceConfig = {
                  User = "restic";
                  Group = "restic";
                };

                path = [ pkgs.restic ];

                script = ''
                  ${pkgs.restic-forget}/bin/restic-forget \
                    --forget-args "${lib.strings.concatStringsSep " " fc.opts}" \
                    ${lib.optionalString (repo_cfg.packSize != null) "--pack-size ${toString repo_cfg.packSize}"} \
                    ${lib.optionalString (fc.maxSize != null) "--max-size ${toString fc.maxSize}"} \
                    ${lib.optionalString (fc.maxSize != null) "--min-age-days ${toString fc.minAgeDays}"} \
                    ${lib.optionalString fc.repackSmall "--repack-small"} \
                    ${lib.optionalString (!fc.repackSmall) "--max-repack-size 0"}
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
                    ${lib.optionalString (to_repo.cfg.packSize != null) "--pack-size ${toString to_repo.cfg.packSize}"} \
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
            requires = [ "nebula-online@jakehillion.service" ];
            after = [ "nebula-online@jakehillion.service" ];
          };
        }
        // lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetService name value)) cfg.repos
        // mapClones mkCloneService;

        timers = lib.mapAttrs' (name: value: lib.attrsets.nameValuePair ("restic-forget-" + name) (mkForgetTimer value)) cfg.repos
          // mapClones mkCloneTimer;
      };
  };
}
