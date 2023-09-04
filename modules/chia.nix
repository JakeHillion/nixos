{ config, pkgs, lib, chia, ... }:

let
  cfg = config.custom.chia;
  chiaPkg = chia.legacyPackages.x86_64-linux.chia;

  ctl = pkgs.writeScriptBin "chiactl" ''
    #! ${pkgs.runtimeShell}
    sudo=exec
    if [[ "$USER" != chia ]]; then
      sudo='exec /run/wrappers/bin/sudo -u chia'
    fi

    $sudo ${chiaPkg}/bin/chia "$@"
  '';
in
{
  options.custom.chia = {
    enable = lib.mkEnableOption "chia";

    path = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/chia";
    };
    keyFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    keyLabel = lib.mkOption {
      type = lib.types.str;
      default = "default";
    };
    targetAddress = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    plotDirectories = lib.mkOption {
      type = with lib.types; nullOr (listOf str);
      default = null;
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ ctl ];

    users.groups.chia = { };
    users.users.chia = {
      home = cfg.path;
      createHome = true;
      isSystemUser = true;
      group = "chia";
    };

    systemd.services.chia = {
      description = "Chia daemon.";
      wantedBy = [ "multi-user.target" ];

      preStart = lib.strings.concatStringsSep "\n" ([ "${chiaPkg}/bin/chia init" ]
        ++ (if cfg.keyFile == null then [ ] else [ "${chiaPkg}/bin/chia keys add -f ${cfg.keyFile} -l '${cfg.keyLabel}'" ])
        ++ (if cfg.targetAddress == null then [ ] else [
        ''
          ${pkgs.yq-go}/bin/yq e \
              '.farmer.xch_target_address = "${cfg.targetAddress}" | .pool.xch_target_address = "${cfg.targetAddress}"' \
              -i ${cfg.path}/.chia/mainnet/config/config.yaml
        ''
      ]) ++ (if cfg.plotDirectories == null then [ ] else [
        ''
          ${pkgs.yq-go}/bin/yq e \
              '.harvester.plot_directories = [${lib.strings.concatMapStringsSep "," (x: "\"" + x + "\"") cfg.plotDirectories}]' \
              -i ${cfg.path}/.chia/mainnet/config/config.yaml
        ''
      ]));
      script = "${chiaPkg}/bin/chia start farmer";
      preStop = "${chiaPkg}/bin/chia stop -d farmer";

      serviceConfig = {
        Type = "forking";

        User = "chia";
        Group = "chia";

        WorkingDirectory = cfg.path;

        Restart = "always";
        RestartSec = 10;
        TimeoutStopSec = 120;
        OOMScoreAdjust = 1000;

        Nice = 2;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 8444 ];
    };
  };
}


