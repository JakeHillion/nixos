{ config, lib, pkgs, ... }:

let
  cfg = config.custom.impermanence;
  usesVarLibPrivate = builtins.any
    (dir: lib.strings.hasPrefix "/var/lib/private/"
      (if builtins.isString dir then dir else dir.directory or dir.dirPath or ""))
    (lib.lists.flatten (lib.attrsets.mapAttrsToList
      (path: cfg: cfg.directories or [ ])
      config.environment.persistence));
in
{
  options.custom.impermanence = {
    enable = lib.mkEnableOption "impermanence";

    base = lib.mkOption {
      type = lib.types.str;
      default = "/data";
    };
    cache = {
      enable = lib.mkEnableOption "impermanence.cache";
      path = lib.mkOption {
        type = lib.types.str;
        default = "/cache";
      };
    };

    extraDirs = lib.mkOption {
      type = with lib.types; listOf (either str (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "The target file path (required)";
          };

          initialContent = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Optional path to a file whose contents to seed into `path`";
          };
        };
      }
      ));
      default = [ ];
    };

    users = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "root" config.custom.user ];
    };

    userExtraFiles = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      default = { };
    };
    userExtraDirs = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${cfg.base}.neededForBoot = true;

    services = {
      openssh.hostKeys = [
        { path = "${cfg.base}/system/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
        { path = "${cfg.base}/system/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
      ];
    };

    custom.chia = lib.mkIf config.custom.chia.enable {
      path = lib.mkOverride 999 "${cfg.base}/chia";
    };

    services.plex = lib.mkIf config.services.plex.enable {
      dataDir = lib.mkOverride 999 "${cfg.base}/plex";
    };

    environment.persistence = lib.mkMerge [
      {
        "${cfg.base}/system" = {
          hideMounts = true;

          directories = [
            "/etc/nixos"
            "/var/lib/systemd/timers" # persistent timer "stamp" files, e.g. "stamp-nix-gc.timer"
          ] ++
          cfg.extraDirs ++
          (lib.lists.optional config.services.postgresql.enable config.services.postgresql.dataDir) ++
          (lib.lists.optional config.hardware.bluetooth.enable "/var/lib/bluetooth") ++
          (lib.lists.optional (config.virtualisation.oci-containers.containers != { }) "/var/lib/containers") ++
          (lib.lists.optional config.services.caddy.enable "/var/lib/caddy");
        };
      }
      (lib.mkIf cfg.cache.enable {
        "${cfg.cache.path}/system" = {
          hideMounts = true;

          directories = (lib.lists.optional config.services.postgresqlBackup.enable config.services.postgresqlBackup.location);
        };
      })
    ];

    home-manager.users =
      let
        mkUser = (x:
          let
            homeCfg = config.home-manager.users."${x}";
          in
          {
            name = x;
            value = {
              home = {
                persistence."${cfg.base}/users/${x}" = {
                  allowOther = false;

                  files = (cfg.userExtraFiles.${x} or [ ]) ++
                    (lib.lists.optionals (config.custom.home.devbox && x == config.custom.user) [ ".local/share/nix/trusted-settings.json" ]) ++
                    (lib.lists.optionals (config.custom.home.devbox && x == config.custom.user) [ ".claude.json" ]);
                  directories = (cfg.userExtraDirs.${x} or [ ]) ++
                    (lib.lists.optionals (config.custom.home.devbox && x == config.custom.user) [ ".claude" ]);
                };

                sessionVariables = lib.attrsets.optionalAttrs homeCfg.programs.zoxide.enable { _ZO_DATA_DIR = "${cfg.base}/users/${x}/.local/share/zoxide"; };
              };

              programs = {
                zsh.history.path = lib.mkOverride 999 "${cfg.base}/users/${x}/.zsh_history";
              };
            };
          });
      in
      builtins.listToAttrs (builtins.map mkUser cfg.users);

    systemd.tmpfiles.rules = lib.lists.flatten (builtins.map
      (user:
        let details = config.users.users.${user}; in [
          "d ${cfg.base}/users/${user} 0700 ${user} ${details.group} - -"
          "L ${details.home}/local - ${user} ${details.group} - ${cfg.base}/users/${user}"
        ])
      cfg.users);

    systemd.services.fix-var-lib-private-permissions = lib.mkIf usesVarLibPrivate {
      description = "Fix /var/lib/private permissions";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 0700 /var/lib/private";
        User = "root";
      };
    };

    systemd.timers.fix-var-lib-private-permissions = lib.mkIf usesVarLibPrivate {
      description = "Fix /var/lib/private permissions every 30 seconds";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        Unit = "fix-var-lib-private-permissions.service";
      };
    };
  };
}
