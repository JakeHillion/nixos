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
        { path = "/data/system/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
        { path = "/data/system/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
      ];
      matrix-synapse.dataDir = "${cfg.base}/system/var/lib/matrix-synapse";
      gitea.stateDir = "${cfg.base}/system/var/lib/gitea";
    };

    custom.chia = lib.mkIf config.custom.chia.enable {
      path = lib.mkOverride 999 "/data/chia";
    };

    environment.persistence = lib.mkMerge [
      {
        "${cfg.base}/system" = {
          hideMounts = true;

          directories = [
            "/etc/nixos"
          ] ++ (lib.lists.optional config.services.tailscale.enable "/var/lib/tailscale") ++
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
        mkUser = (x: {
          name = x;
          value = {
            home = {
              persistence."/data/users/${x}" = {
                allowOther = false;

                files = cfg.userExtraFiles.${x} or [ ];
                directories = cfg.userExtraDirs.${x} or [ ];
              };
              file.".zshrc".text = lib.mkForce ''
                HISTFILE=/data/users/${x}/.zsh_history
              '';
            };
          };
        });
      in
      builtins.listToAttrs (builtins.map mkUser cfg.users);

    systemd.tmpfiles.rules = lib.lists.flatten (builtins.map
      (user:
        let details = config.users.users.${user}; in [
          "d /data/users/${user} 0700 ${user} ${details.group} - -"
          "L ${details.home}/local - ${user} ${details.group} - /data/users/${user}"
        ])
      cfg.users);
  };
}
