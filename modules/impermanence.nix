{ config, lib, pkgs, utils, ... }:

let
  cfg = config.custom.impermanence;

  # Wanted by (not required by) the mount so that restarting this unit never
  # propagates to the mount and unmounts a cache that is in use.
  resetCacheUnit = mountPoint: unit: {
    description = "Recreate ${cfg.cache.path} as an empty btrfs subvolume";
    wantedBy = [ "${utils.escapeSystemdPath mountPoint}.mount" ];
    before = [ "${utils.escapeSystemdPath mountPoint}.mount" ];
    requires = [ "${utils.escapeSystemdPath cfg.cache.device}.device" ];
    after = [ "${utils.escapeSystemdPath cfg.cache.device}.device" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  } // unit;

  # Unless mountPoint is already mounted, mounts the btrfs top level at $top and
  # replaces the cache subvolume with an empty one, running extra before $top is
  # unmounted. Never touches a subvolume that is in use at mountPoint.
  recreateCacheSubvolume = { mountPoint, extra ? "" }: ''
    while read -r _ mnt _; do
      if [ "$mnt" = ${mountPoint} ]; then
        echo "${mountPoint} is already mounted, leaving it alone"
        exit 0
      fi
    done < /proc/self/mounts

    top=$(mktemp -d -p /run reset-cache.XXXXXX)
    mount -t btrfs -o subvolid=5 ${cfg.cache.device} "$top"
    trap 'umount "$top" && rmdir "$top"' EXIT

    if [ -e "$top/${cfg.cache.subvolume}" ]; then
      btrfs subvolume delete --recursive "$top/${cfg.cache.subvolume}"
    fi
    btrfs subvolume create "$top/${cfg.cache.subvolume}"
    chmod 1777 "$top/${cfg.cache.subvolume}"
    ${extra}
  '';
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
      device = lib.mkOption {
        type = lib.types.strMatching "/dev/.+";
        example = "/dev/mapper/disk0-crypt";
        description = "Block device of the btrfs filesystem holding the cache subvolume. Must be btrfs.";
      };
      subvolume = lib.mkOption {
        type = lib.types.str;
        default = "cache";
        description = "Name of the subvolume directly under the btrfs top level (subvolid=5), recreated empty on every boot and mounted at path.";
      };
      extraDirs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "Directories to persist on the cache mount (wiped on boot, on real storage in the meantime).";
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
    fileSystems = lib.mkMerge [
      {
        ${cfg.base}.neededForBoot = true;
      }
      (lib.mkIf cfg.cache.enable (
        # If the cache cannot be prepared, carry on with it and the directories
        # persisted on it in RAM rather than failing local-fs.target and
        # dropping to emergency mode. nofail drops the ordering before the
        # filesystem targets, so add it back: boot still waits for the mounts.
        let
          nofail = [
            "nofail"
            "x-systemd.before=local-fs.target"
            "x-systemd.before=initrd-fs.target"
          ];
          cacheDirs = builtins.map
            (d: if builtins.isString d then d else d.directory)
            (config.environment.persistence."${cfg.cache.path}/system".directories or [ ]);
        in
        {
          ${cfg.cache.path} = {
            device = cfg.cache.device;
            fsType = "btrfs";
            options = [ "subvol=${cfg.cache.subvolume}" ] ++ nofail;
            neededForBoot = true;
          };
        } // lib.attrsets.genAttrs cacheDirs (_: { options = nofail; })
      ))
      (
        # nixpkgs 26.05 dropped the "auto" default for fileSystems.<name>.fsType.
        # impermanence creates bind-mount fileSystems entries without setting
        # fsType, so supply "none" for every persisted directory.
        let
          inherit (lib) attrsets lists strings;
          collectRootDirs = pcfg:
            builtins.map
              (d: if builtins.isString d then d else d.directory)
              (pcfg.directories or [ ]);
          collectUserDirs = pcfg:
            lists.flatten (attrsets.mapAttrsToList
              (user: ucfg:
                let homeDir = config.users.users.${user}.home or "/home/${user}"; in
                builtins.map
                  (d:
                    let sub = if builtins.isString d then d else d.directory; in
                    "${homeDir}/${sub}")
                  (ucfg.directories or [ ]))
              (pcfg.users or { }));
          allDirs = lists.flatten (attrsets.mapAttrsToList
            (_: pcfg: collectRootDirs pcfg ++ collectUserDirs pcfg)
            config.environment.persistence);
          prependSlash = d: if strings.hasPrefix "/" d then d else "/" + d;
        in
        attrsets.listToAttrs (builtins.map
          (d: { name = prependSlash d; value = { fsType = lib.mkDefault "none"; }; })
          allDirs)
      )
    ];

    # The cache is a disk-backed /tmp. Whenever it is about to be mounted and
    # isn't already, its subvolume is recreated empty: in the initrd on every
    # boot, and in the running system when the cache is enabled live.
    boot.initrd.systemd.services.reset-cache = lib.mkIf cfg.cache.enable (resetCacheUnit "/sysroot${cfg.cache.path}" {
      script = recreateCacheSubvolume { mountPoint = "/sysroot${cfg.cache.path}"; };
    });
    systemd.services.reset-cache = lib.mkIf cfg.cache.enable (resetCacheUnit cfg.cache.path {
      # Only ever started by cache.mount; never re-run by a switch.
      restartIfChanged = false;
      path = [ pkgs.btrfs-progs pkgs.util-linux ];
      script = recreateCacheSubvolume {
        mountPoint = cfg.cache.path;
        # Activation has already created impermanence's directories at the
        # unmounted mount point. Recreate them on the new subvolume so their
        # bind mounts find their sources.
        extra = ''
          if [ -d ${cfg.cache.path} ]; then
            (cd ${cfg.cache.path} && find . -mindepth 1 -type d) | while read -r dir; do
              mkdir "$top/${cfg.cache.subvolume}/$dir"
              chown --reference="${cfg.cache.path}/$dir" "$top/${cfg.cache.subvolume}/$dir"
              chmod --reference="${cfg.cache.path}/$dir" "$top/${cfg.cache.subvolume}/$dir"
            done
          fi
        '';
      };
    });

    services = {
      openssh.hostKeys = [
        { path = "${cfg.base}/system/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
        { path = "${cfg.base}/system/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
      ];
    };

    environment.persistence = lib.mkMerge [
      {
        "${cfg.base}/system" = {
          hideMounts = true;

          directories = [
            "/etc/nixos"
            "/var/lib/systemd/timers" # persistent timer "stamp" files, e.g. "stamp-nix-gc.timer"
          ] ++
          cfg.extraDirs ++
          (lib.lists.optional config.services.postgresql.enable config.services.postgresql.dataDir) ++
          (lib.lists.optional config.hardware.bluetooth.enable "/var/lib/bluetooth") ++
          (lib.lists.optional (config.virtualisation.oci-containers.containers != { }) "/var/lib/containers") ++
          (lib.lists.optional config.custom.services.async_coder.enable "/var/lib/async-coder") ++
          (lib.lists.optional config.services.caddy.enable "/var/lib/caddy") ++
          (lib.lists.optional config.services.unbound.enable "/var/lib/unbound") ++
          (lib.lists.optional config.services.ntfy-sh.enable "/var/lib/private/ntfy-sh");
        };
      }
      (lib.mkIf cfg.cache.enable {
        "${cfg.cache.path}/system" = {
          hideMounts = true;

          directories = cfg.cache.extraDirs ++
            (lib.lists.optional config.services.postgresqlBackup.enable config.services.postgresqlBackup.location);
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
    };

    system.activationScripts =
      let
        usesPrivateDir = subdir:
          builtins.any
            (dir: lib.strings.hasPrefix "/var/${subdir}/private/"
              (if builtins.isString dir then dir else dir.directory or dir.dirPath or ""))
            (lib.lists.flatten (lib.attrsets.mapAttrsToList
              (path: cfg: cfg.directories or [ ])
              config.environment.persistence));
      in
      lib.optionalAttrs (usesPrivateDir "lib")
        {
          fix-var-lib-private-permissions = {
            text = "${lib.getExe' pkgs.coreutils "chmod"} 0700 /var/lib/private";
            deps = [ "createPersistentStorageDirs" ];
          };
        } // lib.optionalAttrs (usesPrivateDir "cache") {
        fix-var-cache-private-permissions = {
          text = "${lib.getExe' pkgs.coreutils "chmod"} 0700 /var/cache/private";
          deps = [ "createPersistentStorageDirs" ];
        };
      };
  };
}
