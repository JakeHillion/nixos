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
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${cfg.base}.neededForBoot = true;

    services.openssh.hostKeys = [
      { path = "/data/system/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
      { path = "/data/system/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
    ];

    environment.persistence."${cfg.base}/system" = {
      hideMounts = true;

      directories = [
        "/etc/nixos"
      ] ++ (listIf config.custom.tailscale.enable [ "/var/lib/tailscale" ]) ++
      (listIf config.services.zigbee2mqtt.enable [ config.services.zigbee2mqtt.dataDir ]);
    };

    home-manager.users =
      let
        mkUser = (x: {
          name = x;
          value = {
            home.persistence."/data/users/${x}" = {
              files = [
                ".zsh_history"
              ];
            };
          };
        });
      in
      builtins.listToAttrs (builtins.map mkUser cfg.users);

    systemd.tmpfiles.rules = builtins.map (x: "L ${config.users.users.${x}.home}/local - - - - /data/users/${x}") cfg.users;
  };
}
