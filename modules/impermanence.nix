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
    fileSystems = {
      ${cfg.base}.neededForBoot = true;
    } // (
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
    );

    services = {
      openssh.hostKeys = [
        { path = "${cfg.base}/system/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
        { path = "${cfg.base}/system/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
      ];
    };

    custom.chia = lib.mkIf config.custom.chia.enable {
      path = lib.mkOverride 999 "${cfg.base}/chia";
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
          (lib.lists.optional config.services.tailscale.enable "/var/lib/tailscale") ++
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
