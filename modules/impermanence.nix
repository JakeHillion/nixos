{ config, lib, pkgs, ... }:

let
  cfg = config.custom.impermanence;
  userNames = builtins.attrNames cfg.users;
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

    # Renamed from extraDirs - primary option for system directories
    directories = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "System directories to persist";
    };

    # Restructured to match upstream impermanence API
    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          directories = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
            description = "User directories to persist (relative to home)";
          };
          files = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
            description = "User files to persist (relative to home)";
          };
        };
      });
      default = { };
      description = "Per-user persistence configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add base directories as defaults
    custom.impermanence.directories = lib.mkBefore ([
      "/etc/nixos"
      "/var/lib/systemd/timers"
    ] ++
    (lib.lists.optional config.services.postgresql.enable config.services.postgresql.dataDir) ++
    (lib.lists.optional config.hardware.bluetooth.enable "/var/lib/bluetooth") ++
    (lib.lists.optional (config.virtualisation.oci-containers.containers != { }) "/var/lib/containers") ++
    (lib.lists.optional config.services.caddy.enable "/var/lib/caddy") ++
    (lib.lists.optional config.services.tailscale.enable "/var/lib/tailscale") ++
    (lib.lists.optional config.services.unbound.enable "/var/lib/unbound"));

    # Ensure root and custom.user have default entries
    custom.impermanence.users = {
      root = lib.mkDefault { };
      ${config.custom.user} = lib.mkDefault { };
    };

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

    systemd =
      let
        # Cache directories to persist
        cacheDirs = lib.lists.optional config.services.postgresqlBackup.enable config.services.postgresqlBackup.location;
      in
      {
        mounts =
          # System directories
          (builtins.map
            (d: {
              what = "${cfg.base}/system${d}";
              where = d;
              type = "none";
              options = "bind,x-gvfs-hide";
              wantedBy = [ "local-fs.target" ];
              before = [ "local-fs.target" ];
              unitConfig.DefaultDependencies = false;
            })
            cfg.directories) ++
          # Cache directories
          (lib.lists.optionals cfg.cache.enable (builtins.map
            (d: {
              what = "${cfg.cache.path}/system${d}";
              where = d;
              type = "none";
              options = "bind,x-gvfs-hide";
              wantedBy = [ "local-fs.target" ];
              before = [ "local-fs.target" ];
              unitConfig.DefaultDependencies = false;
            })
            cacheDirs)) ++
          # User directories
          (lib.lists.flatten (builtins.map
            (user:
              let
                userCfg = config.users.users.${user};
                userHome = userCfg.home;
                dirs = cfg.users.${user}.directories or [ ];
              in
              builtins.map
                (d: {
                  what = "${cfg.base}/users/${user}/${d}";
                  where = "${userHome}/${d}";
                  type = "none";
                  options = "bind,x-gvfs-hide";
                  wantedBy = [ "local-fs.target" ];
                  before = [ "local-fs.target" ];
                  unitConfig.DefaultDependencies = false;
                })
                dirs)
            userNames));

        tmpfiles.rules =
          # User directories and files
          (lib.lists.flatten (builtins.map
            (user:
              let
                details = config.users.users.${user};
                files = cfg.users.${user}.files or [ ];
              in
              [
                # Create per-user nix profile directory (required for home-manager)
                "d /nix/var/nix/profiles/per-user/${user} 0755 ${user} ${details.group} - -"
                "d ${cfg.base}/users/${user} 0700 ${user} ${details.group} - -"
                "L ${details.home}/local - ${user} ${details.group} - ${cfg.base}/users/${user}"
              ] ++
              (builtins.map (f: "L ${details.home}/${f} - ${user} ${details.group} - ${cfg.base}/users/${user}/${f}") files))
            userNames));

        services = lib.foldl' lib.recursiveUpdate { } (builtins.map
          (subdir:
            let
              usesPrivateDir = builtins.any
                (dir: lib.strings.hasPrefix "/var/${subdir}/private/" dir)
                cfg.directories;
            in
            {
              "fix-var-${subdir}-private-permissions" = lib.mkIf usesPrivateDir {
                description = "Fix /var/${subdir}/private permissions";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 0700 /var/${subdir}/private";
                  User = "root";
                };
              };
            }) [ "lib" "cache" ]);

        timers = lib.foldl' lib.recursiveUpdate { } (builtins.map
          (subdir:
            let
              usesPrivateDir = builtins.any
                (dir: lib.strings.hasPrefix "/var/${subdir}/private/" dir)
                cfg.directories;
            in
            {
              "fix-var-${subdir}-private-permissions" = lib.mkIf usesPrivateDir {
                description = "Fix /var/${subdir}/private permissions every 30 seconds";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnBootSec = "30s";
                  OnUnitActiveSec = "30s";
                  Unit = "fix-var-${subdir}-private-permissions.service";
                };
              };
            }) [ "lib" "cache" ]);
      };
  };
}
