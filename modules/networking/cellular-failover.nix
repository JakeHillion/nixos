# Cellular (4G) failover for the primary WAN.
#
# Model: the primary WAN gets its default route from dhcpcd (metric
# `1000 + ifindex`, never removed while the lease holds). The cellular
# failover keeps a static default route (metric 2048 = standBy) and the
# monitor here merely flips that *cellular* route's metric:
#   - healthy:  cellular metric 2048 (high)  -> primary WAN wins
#   - failed:   cellular metric 999          -> cellular wins
#
# Because the primary route is never taken down, a probe bound to the
# primary interface can always verify the primary's *upstream* reachability
# (not just link state), which is what catches ISP maintenance where the
# modem stays up but has no transit.
{ config, lib, pkgs, ... }:

let
  cfg = config.custom.networking.cellularFailover;

  script = pkgs.writeShellScript "cellular-failover" ''
    set -u

    PRIMARY_IFACE=${lib.escapeShellArg cfg.primaryInterface}
    IFACE=${lib.escapeShellArg cfg.interface}
    GATEWAY=${lib.escapeShellArg cfg.gateway}
    STANDBY_METRIC=${toString cfg.standbyMetric}
    ACTIVE_METRIC=${toString cfg.activeMetric}
    CHECK_INTERVAL=${toString cfg.checkInterval}
    RECOVERY_INTERVAL=${toString cfg.recoveryInterval}
    REQUIRED_SUCCESSES=${toString cfg.requiredRecoveryChecks}
    PING_COUNT=${toString cfg.pingCount}
    PING_TIMEOUT=${toString cfg.pingTimeout}

    STATE_DIR=/run/cellular-failover
    STATE_FILE="$STATE_DIR/state"

    ip=${pkgs.iproute2}/bin/ip
    ping=${pkgs.iputils}/bin/ping

    # Does the primary WAN currently carry a default route?
    primary_has_route() {
      "$ip" -o route show default | grep -qw "dev $PRIMARY_IFACE"
    }

    # A handful of pings back to back, bound to the primary WAN interface.
    probe() {
      "$ping" -I "$PRIMARY_IFACE" -n -c "$PING_COUNT" -W "$PING_TIMEOUT" "$1" >/dev/null 2>&1
    }

    # Upstream considered reachable iff ANY probe target answers.
    upstream_up() {
      local t
      for t in ${builtins.concatStringsSep " " (map lib.escapeShellArg cfg.probeTargets)}; do
        if probe "$t"; then return 0; fi
      done
      return 1
    }

    read_state() {
      if [[ -f "$STATE_FILE" ]]; then cat "$STATE_FILE"; else echo standby; fi
    }

    write_state() {
      mkdir -p "$STATE_DIR"
      echo "$1" > "$STATE_FILE"
    }

    # Replace any existing cellular default route with one at the given metric.
    set_cellular_metric() {
      local metric="$1"
      "$ip" route del default via "$GATEWAY" dev "$IFACE" 2>/dev/null || true
      "$ip" route add default via "$GATEWAY" dev "$IFACE" metric "$metric"
    }

    fail_over() {
      set_cellular_metric "$ACTIVE_METRIC"
      write_state active
      log "primary upstream down; failing over to cellular ($ACTIVE_METRIC)"
    }

    restore_primary() {
      set_cellular_metric "$STANDBY_METRIC"
      write_state standby
      log "primary restored; cellular to standby ($STANDBY_METRIC)"
    }

    log() { echo "$(date -Is) $*"; }

    state=$(read_state)
    [[ "$state" == active ]] || state=standby
    success_streak=0

    # Reconcile the kernel route to the persisted state (true-up after boot).
    if [[ "$state" == active ]]; then
      set_cellular_metric "$ACTIVE_METRIC"
    else
      set_cellular_metric "$STANDBY_METRIC"
    fi
    log "monitor starting (state=$state)"

    while true; do
      if primary_has_route; then
        if upstream_up; then
          if [[ "$state" == active ]]; then
            success_streak=$((success_streak + 1))
            log "primary upstream reachable ($success_streak/$REQUIRED_SUCCESSES)"
            if (( success_streak >= REQUIRED_SUCCESSES )); then
              restore_primary
              success_streak=0
            else
              sleep "$RECOVERY_INTERVAL"
              continue
            fi
          fi
          sleep "$CHECK_INTERVAL"
        else
          success_streak=0
          if [[ "$state" == standby ]]; then
            fail_over
          fi
          sleep "$CHECK_INTERVAL"
        fi
      else
        # No primary route yet (e.g. DHCP at boot). Don't flip state; the
        # standby route may briefly be the only default meanwhile.
        success_streak=0
        sleep "$CHECK_INTERVAL"
      fi
    done
  '';
in
{
  options.custom.networking.cellularFailover = {
    enable = lib.mkEnableOption "primary WAN health check with cellular failover";

    primaryInterface = lib.mkOption {
      type = lib.types.str;
      description = "Primary WAN interface to probe (must keep its default route).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Failover interface carrying the toggleable default route.";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      description = "Gateway on the failover interface.";
    };

    standbyMetric = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "Failover route metric when healthy (kept above the primary).";
    };

    activeMetric = lib.mkOption {
      type = lib.types.int;
      default = 999;
      description = "Failover route metric after failover (kept below the primary).";
    };

    probeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "Upstream targets pinged via the primary interface. Failure requires ALL targets to fail.";
    };

    pingCount = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "How many pings to send to each target per check.";
    };

    pingTimeout = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Seconds to wait for each ping reply.";
    };

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Seconds between checks in the healthy/steady state.";
    };

    recoveryInterval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Minimum seconds between successful recovery checks while failed over.";
    };

    requiredRecoveryChecks = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Consecutive successful checks (spaced recoveryInterval) required to restore the primary.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.cellular-failover = {
      description = "Primary WAN health check and cellular failover";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${script}";
        Restart = "on-failure";
        RestartSec = "10";
        RuntimeDirectory = "cellular-failover";
        RuntimeDirectoryMode = "0755";
        # Needs root to re-route and to bind probes to the primary interface.
      };
    };
  };
}
