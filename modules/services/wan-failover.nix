{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.wan-failover;
  routerCfg = config.custom.router;

  # Script to monitor and manage failover
  failoverScript = pkgs.writeScript "wan-failover" ''
    #!${pkgs.runtimeShell}
    set -euo pipefail

    # Configuration
    PRIMARY_IF="${cfg.primaryInterface}"
    SECONDARY_IF="${cfg.secondaryInterface}"
    PRIMARY_METRIC=${toString cfg.primaryMetric}
    SECONDARY_METRIC=${toString cfg.secondaryMetric}
    CHECK_INTERVAL=${toString cfg.checkInterval}
    FAILURE_THRESHOLD=${toString cfg.failureThreshold}
    RECOVERY_THRESHOLD=${toString cfg.recoveryThreshold}
    PING_HOSTS="${lib.strings.concatStringsSep " " cfg.pingHosts}"
    STATE_FILE="${cfg.stateFile}"
    IP_CACHE_FILE="${cfg.stateFile}.ip-cache"

    # Logging helper
    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.systemd}/bin/systemd-cat -t wan-failover
    }

    # Get current state
    get_state() {
      if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
      else
        echo "primary"
      fi
    }

    # Set state
    set_state() {
      echo "$1" > "$STATE_FILE"
    }

    # Get consecutive failures
    get_consecutive() {
      local file="$2"
      if [[ -f "$file" ]]; then
        cat "$file"
      else
        echo "0"
      fi
    }

    # Set consecutive count
    set_consecutive() {
      echo "$1" > "$2"
    }

    # Check if primary WAN is healthy
    check_primary() {
      local success=0
      local total=0

      for host in $PING_HOSTS; do
        total=$((total + 1))
        # Ping via primary WAN using the interface IP
        if ${pkgs.iputils}/bin/ping -c 1 -W 3 -I "$PRIMARY_IF" "$host" >/dev/null 2>&1; then
          success=$((success + 1))
        fi
      done

      # Require at least half of hosts to respond
      if [[ $success -ge $((total / 2 + 1)) ]]; then
        return 0
      else
        return 1
      fi
    }

    # Update secondary WAN IP in nftables
    update_secondary_ip() {
      ${lib.optionalString (cfg.secondaryIpCommand != null) ''
        local new_ip
        new_ip=$(${cfg.secondaryIpCommand} 2>/dev/null || echo "")

        if [[ -n "$new_ip" && "$new_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          local old_ip
          old_ip=$(get_consecutive "" "$IP_CACHE_FILE" 2>/dev/null || echo "")

          if [[ "$new_ip" != "$old_ip" ]]; then
            # Update nftables set
            if ${pkgs.nftables}/bin/nft list set ip nat wan_loopback_ips >/dev/null 2>&1; then
              # Remove old IP if different
              if [[ -n "$old_ip" && "$old_ip" != "$new_ip" ]]; then
                ${pkgs.nftables}/bin/nft delete element ip nat wan_loopback_ips { "$old_ip" } 2>/dev/null || true
              fi
              # Add new IP
              ${pkgs.nftables}/bin/nft add element ip nat wan_loopback_ips { "$new_ip" } 2>/dev/null || log "Failed to add IP $new_ip to nftables set"
              log "Updated secondary WAN IP in nftables: $new_ip"
            fi
            set_consecutive "$new_ip" "$IP_CACHE_FILE"
          fi
        fi
      ''}
    }

    # Switch to secondary WAN
    switch_to_secondary() {
      log "Switching to secondary WAN"

      # Increase primary route metric (making it less preferred)
      ${pkgs.iproute2}/bin/ip route change default dev "$PRIMARY_IF" metric 300 2>/dev/null || true

      # Ensure secondary has better metric
      ${pkgs.iproute2}/bin/ip route change default dev "$SECONDARY_IF" metric "$SECONDARY_METRIC" 2>/dev/null || \
        ${pkgs.iproute2}/bin/ip route add default dev "$SECONDARY_IF" metric "$SECONDARY_METRIC" 2>/dev/null || true

      set_state "secondary"
      log "Now using secondary WAN"
    }

    # Switch back to primary WAN
    switch_to_primary() {
      log "Switching back to primary WAN"

      # Restore primary route metric
      ${pkgs.iproute2}/bin/ip route change default dev "$PRIMARY_IF" metric "$PRIMARY_METRIC" 2>/dev/null || \
        ${pkgs.iproute2}/bin/ip route add default dev "$PRIMARY_IF" metric "$PRIMARY_METRIC" 2>/dev/null || true

      # Increase secondary route metric
      ${pkgs.iproute2}/bin/ip route change default dev "$SECONDARY_IF" metric "$SECONDARY_METRIC" 2>/dev/null || true

      set_state "primary"
      log "Now using primary WAN"
    }

    # Main monitoring loop
    monitor() {
      local state
      local failures
      local successes

      # Initial route setup - ensure both routes exist with correct metrics
      log "Initializing WAN failover monitoring"

      # Ensure primary default route exists with primary metric
      if ! ${pkgs.iproute2}/bin/ip route | grep -q "default.*$PRIMARY_IF.*metric $PRIMARY_METRIC"; then
        ${pkgs.iproute2}/bin/ip route add default dev "$PRIMARY_IF" metric "$PRIMARY_METRIC" 2>/dev/null || true
      fi

      # Ensure secondary default route exists with secondary metric (higher = lower priority)
      if ! ${pkgs.iproute2}/bin/ip route | grep -q "default.*$SECONDARY_IF.*metric $SECONDARY_METRIC"; then
        ${pkgs.iproute2}/bin/ip route add default dev "$SECONDARY_IF" metric "$SECONDARY_METRIC" 2>/dev/null || \
          ${pkgs.iproute2}/bin/ip route change default dev "$SECONDARY_IF" metric "$SECONDARY_METRIC" 2>/dev/null || true
      fi

      state=$(get_state)
      failures=$(get_consecutive "" "${cfg.stateFile}.failures")
      successes=$(get_consecutive "" "${cfg.stateFile}.successes")

      log "Current state: $state, checking connectivity..."

      if check_primary; then
        # Primary is healthy
        successes=$((successes + 1))
        failures=0

        if [[ "$state" == "secondary" && $successes -ge $RECOVERY_THRESHOLD ]]; then
          switch_to_primary
        fi
      else
        # Primary is failing
        failures=$((failures + 1))
        successes=0

        if [[ "$state" == "primary" && $failures -ge $FAILURE_THRESHOLD ]]; then
          switch_to_secondary
        fi
      fi

      # Persist counters
      set_consecutive "$failures" "${cfg.stateFile}.failures"
      set_consecutive "$successes" "${cfg.stateFile}.successes"

      # Update secondary IP (periodically, doesn't need to happen every check)
      if [[ $((successes % 6)) -eq 0 || $((failures % 6)) -eq 0 ]]; then
        update_secondary_ip
      fi
    }

    # Run single check
    monitor
  '';
in
{
  options.custom.services.wan-failover = {
    enable = lib.mkEnableOption "WAN failover service";

    primaryInterface = lib.mkOption {
      type = lib.types.str;
      description = "Primary WAN interface name";
    };

    secondaryInterface = lib.mkOption {
      type = lib.types.str;
      description = "Secondary WAN interface name (cellular/backup)";
    };

    primaryMetric = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Route metric for primary WAN (lower = higher priority)";
    };

    secondaryMetric = lib.mkOption {
      type = lib.types.int;
      default = 200;
      description = "Route metric for secondary WAN (higher = lower priority)";
    };

    pingHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
      description = "Hosts to ping for connectivity check";
    };

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Interval between checks in seconds";
    };

    failureThreshold = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Consecutive failures before switching to secondary";
    };

    recoveryThreshold = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Consecutive successes before switching back to primary";
    };

    secondaryIpCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Shell command to retrieve secondary WAN IP (for NAT loopback). Output must be just the IP.";
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wan-failover/state";
      description = "File to persist failover state";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.primaryMetric < cfg.secondaryMetric;
        message = "Primary WAN metric must be lower than secondary metric for proper failover";
      }
    ];

    # Ensure state directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/wan-failover 0755 root root -"
    ];

    # Systemd service for failover monitoring
    systemd.services.wan-failover = {
      description = "WAN Failover Monitor";
      after = [ "network-online.target" "nftables.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = failoverScript;
        User = "root";
        Group = "root";
        # Allow network operations
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
      };
    };

    # Timer to run checks periodically
    systemd.timers.wan-failover = {
      description = "WAN Failover Monitor Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.checkInterval}s";
        Unit = "wan-failover.service";
      };
    };

    # Install required packages
    environment.systemPackages = with pkgs; [
      iproute2
      iputils
      nftables
    ];
  };
}
