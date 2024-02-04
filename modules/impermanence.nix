{ config, lib, ... }:

let
  cfg = config.custom.impermanence;
  listIf = (enable: x: if enable then x else [ ]);
in
{
  options.custom.impermanence = {
    enable = lib.mkEnableOption "impermanence";

    base = lib.mkOption {
      type = lib.types.str;
      default = "/data";
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

    environment.persistence."${cfg.base}/system" = {
      hideMounts = true;

      directories = [
        "/etc/nixos"
      ] ++ (listIf config.custom.tailscale.enable [ "/var/lib/tailscale" ]) ++
      (listIf config.services.zigbee2mqtt.enable [ config.services.zigbee2mqtt.dataDir ]) ++
      (listIf config.services.postgresql.enable [ config.services.postgresql.dataDir ]) ++
      (listIf config.hardware.bluetooth.enable [ "/var/lib/bluetooth" ]) ++
      (listIf config.custom.services.unifi.enable [ "/var/lib/unifi" ]) ++
      (listIf (config.virtualisation.oci-containers.containers != { }) [ "/var/lib/containers" ]);
    };

    home-manager.users =
      let
        mkUser = (x: {
          name = x;
          value = {
            home.persistence."/data/users/${x}" = {
              files = [
                ".zsh_history"
              ] ++ cfg.userExtraFiles.${x} or [ ];

              directories = cfg.userExtraDirs.${x} or [ ];
            };
          };
        });
      in
      builtins.listToAttrs (builtins.map mkUser cfg.users);

    systemd.tmpfiles.rules = builtins.map
      (user:
        let details = config.users.users.${user}; in "L ${details.home}/local - ${user} ${details.group} - /data/users/${user}")
      cfg.users;
  };
}
