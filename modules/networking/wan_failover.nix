{ config, pkgs, lib, ... }:

let
  cfg = config.custom.networking.wanFailover;

  # Metric of the default route installed via the backup while failed over.
  # Must beat whatever the primary's DHCP client installs (dhcpcd uses 1000 +
  # ifindex for wired interfaces).
  failoverMetric = 100;

  # Seconds between probe rounds.
  interval = 5;
  # Consecutive failed rounds before failing over to the backup.
  failThreshold = 3;
  # Consecutive successful rounds before failing back to the primary. Larger
  # than failThreshold so a flapping primary stays on the backup.
  recoverThreshold = 12;

  monitor = pkgs.writeShellApplication {
    name = "wan-failover";
    runtimeInputs = with pkgs; [ iproute2 iputils conntrack-tools ];
    text = ''
      primary=${lib.strings.escapeShellArg cfg.primaryInterface}
      backup=${lib.strings.escapeShellArg cfg.backup.interface}
      gateway=${lib.strings.escapeShellArg cfg.backup.gateway}
      targets=(${lib.strings.escapeShellArgs cfg.targets})

      # A round succeeds if any target answers via the primary. Pings are bound
      # to the primary so it is still probed while the backup is preferred.
      # Each round starts at the next target to spread load across them.
      probe() {
        local i
        for ((i = 0; i < ''${#targets[@]}; i++)); do
          if ping -n -q -c 1 -W 2 -I "$primary" "''${targets[(round + i) % ''${#targets[@]}]}" >/dev/null 2>&1; then
            return 0
          fi
        done
        return 1
      }

      failed_over() {
        [ -n "$(ip -4 route show default dev "$backup" metric ${toString failoverMetric})" ]
      }

      # Masqueraded flows keep the source address of the WAN they started on,
      # so long-lived ones (UDP especially) stay broken after a switch until
      # their conntrack entries are dropped.
      flush_nat() {
        conntrack -D --src-nat >/dev/null 2>&1 || true
      }

      fails=0
      successes=0
      round=0

      if failed_over; then
        echo "starting failed over to $backup"
      else
        echo "starting on $primary"
      fi

      while true; do
        if probe; then
          fails=0
          successes=$((successes + 1))
        else
          successes=0
          fails=$((fails + 1))
        fi

        if failed_over; then
          if [ "$successes" -ge ${toString recoverThreshold} ]; then
            echo "$primary healthy for $successes rounds, failing back"
            ip -4 route del default dev "$backup" metric ${toString failoverMetric}
            flush_nat
          fi
        else
          if [ "$fails" -ge ${toString failThreshold} ]; then
            echo "$primary unhealthy for $fails rounds, failing over to $backup"
            if ip -4 route replace default via "$gateway" dev "$backup" metric ${toString failoverMetric}; then
              flush_nat
            else
              echo "failed to install default route via $backup"
            fi
          fi
        fi

        round=$((round + 1))
        sleep ${toString interval}
      done
    '';
  };
in
{
  options.custom.networking.wanFailover = {
    enable = lib.mkEnableOption "health-checked failover from the primary WAN to a backup";

    primaryInterface = lib.mkOption {
      type = lib.types.str;
      description = "Primary WAN interface, probed for reachability.";
    };

    backup = {
      interface = lib.mkOption {
        type = lib.types.str;
        description = "Backup WAN interface.";
      };
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "Gateway reached via the backup interface.";
      };
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
      description = "Public IPs pinged via the primary. The primary is healthy while any of them answers.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.wan-failover = {
      description = "WAN failover monitor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = lib.meta.getExe monitor;
        Restart = "always";
        RestartSec = "5s";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      };
    };
  };
}
