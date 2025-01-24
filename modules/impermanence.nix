{ config, lib, ... }:

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
      matrix-synapse.dataDir = "${cfg.base}/system/var/lib/matrix-synapse";
      gitea.stateDir = "${cfg.base}/system/var/lib/gitea";
    };

    custom.chia = lib.mkIf config.custom.chia.enable {
      path = lib.mkOverride 999 "${cfg.base}/chia";
    };
    custom.services.frigate = lib.mkIf config.custom.services.frigate.enable {
      dataPath = lib.mkOverride 999 "${cfg.base}/frigate";
    };

    services.resilio = lib.mkIf config.services.resilio.enable {
      directoryRoot = lib.mkOverride 999 "${cfg.base}/sync";
    };

    services.plex = lib.mkIf config.services.plex.enable {
      dataDir = lib.mkOverride 999 "${cfg.base}/plex";
    };

    services.home-assistant = lib.mkIf config.services.home-assistant.enable {
      configDir = lib.mkOverride 999 "/data/home-assistant";
    };

    environment.persistence = lib.mkMerge [
      {
        "${cfg.base}/system" = {
          hideMounts = true;

          directories = [
            "/etc/nixos"
          ] ++
          cfg.extraDirs ++
          (lib.lists.optional config.services.tailscale.enable "/var/lib/tailscale") ++
          (lib.lists.optional config.services.zigbee2mqtt.enable config.services.zigbee2mqtt.dataDir) ++
          (lib.lists.optional config.services.postgresql.enable config.services.postgresql.dataDir) ++
          (lib.lists.optional config.hardware.bluetooth.enable "/var/lib/bluetooth") ++
          (lib.lists.optional config.custom.services.unifi.enable "/var/lib/unifi") ++
          (lib.lists.optional (config.virtualisation.oci-containers.containers != { }) "/var/lib/containers") ++
          (lib.lists.optional config.services.tang.enable "/var/lib/private/tang") ++
          (lib.lists.optional config.services.caddy.enable "/var/lib/caddy") ++
          (lib.lists.optional config.services.prometheus.enable "/var/lib/${config.services.prometheus.stateDir}") ++
          (lib.lists.optional config.custom.services.isponsorblocktv.enable "${config.custom.services.isponsorblocktv.dataDir}") ++
          (lib.lists.optional config.services.step-ca.enable "/var/lib/step-ca/db");
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
            value = args:
              let
                homeConfig = args.config;
              in
              {
                home = {
                  persistence."${cfg.base}/users/${x}" = {
                    allowOther = false;

                    files = cfg.userExtraFiles.${x} or [ ];
                    directories = cfg.userExtraDirs.${x} or [ ];
                  };

                  sessionVariables = lib.attrsets.optionalAttrs homeCfg.programs.zoxide.enable { _ZO_DATA_DIR = "${cfg.base}/users/${x}/.local/share/zoxide"; };

                  file = {
                    "local".source = homeConfig.lib.file.mkOutOfStoreSymlink "${cfg.base}/users/${x}";
                  } //
                  (lib.attrsets.optionalAttrs config.custom.games.steam.enable {
                    ".local/share/Steam".source = homeConfig.lib.file.mkOutOfStoreSymlink "${cfg.base}/users/${x}/games/Steam";
                  });
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
        ])
      cfg.users);
  };
}
