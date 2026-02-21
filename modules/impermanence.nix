{ config, lib, pkgs, ... }:

let
  cfg = config.custom.impermanence;
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
      type = with lib.types; listOf str;
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
          (lib.lists.optional config.custom.services.async_coder.enable "/var/lib/async-coder") ++
          (lib.lists.optional config.services.caddy.enable "/var/lib/caddy") ++
          (lib.lists.optional config.services.tailscale.enable "/var/lib/tailscale") ++
          (lib.lists.optional config.services.unbound.enable "/var/lib/unbound") ++
          (lib.lists.optional config.services.ntfy-sh.enable "/var/lib/private/ntfy-sh");
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

                  files = cfg.userExtraFiles.${x} or [ ];
                  directories = cfg.userExtraDirs.${x} or [ ];
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

    systemd = {
      tmpfiles.rules = lib.lists.flatten (builtins.map
        (user:
          let details = config.users.users.${user}; in [
            "d ${cfg.base}/users/${user} 0700 ${user} ${details.group} - -"
            "L ${details.home}/local - ${user} ${details.group} - ${cfg.base}/users/${user}"
          ])
        cfg.users);
    } // (lib.foldl' lib.recursiveUpdate { } (builtins.map
      (subdir:
        let
          usesPrivateDir = builtins.any
            (dir: lib.strings.hasPrefix "/var/${subdir}/private/"
              (if builtins.isString dir then dir else dir.directory or dir.dirPath or ""))
            (lib.lists.flatten (lib.attrsets.mapAttrsToList
              (path: cfg: cfg.directories or [ ])
              config.environment.persistence));
        in
        {
          services."fix-var-${subdir}-private-permissions" = lib.mkIf usesPrivateDir {
            description = "Fix /var/${subdir}/private permissions";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 0700 /var/${subdir}/private";
              User = "root";
            };
          };

          timers."fix-var-${subdir}-private-permissions" = lib.mkIf usesPrivateDir {
            description = "Fix /var/${subdir}/private permissions every 30 seconds";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "30s";
              OnUnitActiveSec = "30s";
              Unit = "fix-var-${subdir}-private-permissions.service";
            };
          };
        }) [ "lib" "cache" ]));
  };
}
