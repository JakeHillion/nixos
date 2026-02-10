{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.immich;
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "immich";
  };

  config = lib.mkIf cfg.enable {
    age.secrets."immich/restic/b52.key" = {
      file = ../../secrets/restic/b52.age;
      owner = "immich";
      group = "immich";
    };

    users.users.immich.uid = config.ids.uids.immich;
    users.groups.immich.gid = config.ids.gids.immich;

    custom.www.nebula = {
      enable = true;
      virtualHosts."immich.${config.ogygia.domain}".extraConfig = ''
        reverse_proxy http://localhost:${toString config.services.immich.port}
      '';
    };

    services.restic.backups."immich" = {
      repository = "rest:https://restic.${config.ogygia.domain}/b52";
      user = "immich";
      passwordFile = config.age.secrets."immich/restic/b52.key".path;

      timerConfig = {
        OnBootSec = "60m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "5m";
      };

      paths = [ config.services.immich.mediaLocation ];
    };

    services.immich = {
      enable = true;
    };

    systemd.services.immich-restic-clone-trigger = {
      description = "Trigger early b52->AWS restic clones on large Immich backups";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = pkgs.writeShellScript "immich-restic-clone-trigger" ''
          set -euo pipefail

          THRESHOLD_GIB=4

          ${pkgs.systemd}/bin/journalctl -f -u restic-backups-immich.service -o cat \
            | ${pkgs.gnugrep}/bin/grep --line-buffered 'Added to the repository:' \
            | while IFS= read -r line; do
              size=$(echo "$line" | ${pkgs.gawk}/bin/awk '{
                for (i=1; i<=NF; i++) {
                  if ($i == "repository:") {
                    print $(i+1), $(i+2)
                    exit
                  }
                }
              }')

              value=$(echo "$size" | ${pkgs.gawk}/bin/awk '{print $1}')
              unit=$(echo "$size" | ${pkgs.gawk}/bin/awk '{print $2}')

              gib_value=$(${pkgs.gawk}/bin/awk -v val="$value" -v unit="$unit" 'BEGIN {
                if (unit == "TiB") printf "%.6f", val * 1024
                else if (unit == "GiB") printf "%.6f", val
                else if (unit == "MiB") printf "%.6f", val / 1024
                else if (unit == "KiB") printf "%.6f", val / 1048576
                else if (unit == "B") printf "%.6f", val / 1073741824
                else printf "0"
              }')

              exceeds=$(${pkgs.gawk}/bin/awk -v gib="$gib_value" -v threshold="$THRESHOLD_GIB" 'BEGIN {
                print (gib > threshold) ? "1" : "0"
              }')

              if [ "$exceeds" = "1" ]; then
                echo "Detected large backup: ''${value} ''${unit} (''${gib_value} GiB) exceeds ''${THRESHOLD_GIB} GiB threshold"
                echo "Starting early b52->AWS clone services"
                ${pkgs.systemd}/bin/systemctl start restic-clone-b52-aws-eu-central-2.service || echo "Failed to start aws-eu-central-2 clone"
                ${pkgs.systemd}/bin/systemctl start restic-clone-b52-aws-us-east-1.service || echo "Failed to start aws-us-east-1 clone"
              else
                echo "Backup size: ''${value} ''${unit} (''${gib_value} GiB) below ''${THRESHOLD_GIB} GiB threshold"
              fi
            done
        '';
        Restart = "always";
        RestartSec = "60s";
      };
    };
  };
}
