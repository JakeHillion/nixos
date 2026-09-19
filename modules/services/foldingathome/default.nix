{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.foldingathome;

  tariffCode = "E-1R-${cfg.octopus.productCode}-${cfg.octopus.region}";

  # fah-client ships "paused": true in the default resource group
  # (src/resources/group.json) and registers no option to change it, so a fresh
  # client sits idle until something tells it to fold. Its HTTP server exposes a
  # single route, a websocket; everything else redirects to the hosted Web
  # Control. Sending the fold command is idempotent, and the resulting unpaused
  # state is written to client.db.
  unpause = pkgs.writeShellApplication {
    name = "foldingathome-unpause";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      payload='{"cmd":"state","state":"fold"}'

      for attempt in $(seq 60); do
        if exec 3<>/dev/tcp/127.0.0.1/7396; then break; fi
        if [ "$attempt" = 60 ]; then
          echo "timed out waiting for the client to start listening" >&2
          exit 1
        fi
        sleep 1
      done

      printf 'GET /api/websocket HTTP/1.1\r\nHost: 127.0.0.1:7396\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\nSec-WebSocket-Version: 13\r\n\r\n' >&3

      read -r status <&3
      case "$status" in
        *101*) ;;
        *) echo "unexpected handshake response: $status" >&2; exit 1 ;;
      esac

      # Client frames must be masked, but an all zero key leaves the payload as is.
      printf '%b%s' "\x81\x$(printf '%02x' $((0x80 | ''${#payload})))\x00\x00\x00\x00" "$payload" >&3
    '';
  };

  priceGate = pkgs.writeShellApplication {
    name = "foldingathome-price-gate";
    runtimeInputs = with pkgs; [ curl jq coreutils gawk systemd ];
    text = ''
      set -euo pipefail
      : "''${RUNTIME_DIRECTORY:?}"

      API_BASE="https://api.octopus.energy/v1/products/${cfg.octopus.productCode}/electricity-tariffs/${tariffCode}/standard-unit-rates"
      THRESHOLD=${lib.escapeShellArg (toString cfg.maxPriceIncVat)}
      RATES_FILE="$RUNTIME_DIRECTORY/rates.json"

      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      # Half-hourly slots, so an hour either side always brackets the current one.
      PERIOD_FROM=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
      PERIOD_TO=$(date -u -d '1 hour' +%Y-%m-%dT%H:%M:%SZ)

      RATE=""
      for attempt in 1 2 3; do
        if curl -sSf -o "$RATES_FILE" "$API_BASE/?period_from=$PERIOD_FROM&period_to=$PERIOD_TO"; then
          RATE=$(jq -r --arg now "$NOW" '
            .results[]
            | select(.valid_from <= $now and (.valid_to == null or .valid_to > $now))
            | .value_inc_vat
          ' "$RATES_FILE" | head -n1)
          if [ -n "$RATE" ] && [ "$RATE" != "null" ]; then
            break
          fi
          RATE=""
        fi
        echo "attempt $attempt: no usable rate for $NOW"
        sleep 10
      done

      if [ -z "$RATE" ]; then
        # Fail closed: without a price we assume electricity is worth paying for.
        echo "could not determine the current unit rate, stopping folding"
        systemctl stop foldingathome.service
        exit 1
      fi

      if awk -v rate="$RATE" -v threshold="$THRESHOLD" 'BEGIN { exit !(rate < threshold) }'; then
        echo "current rate ''${RATE}p/kWh is below ''${THRESHOLD}p/kWh, folding"
        systemctl start foldingathome.service
      else
        echo "current rate ''${RATE}p/kWh is not below ''${THRESHOLD}p/kWh, not folding"
        systemctl stop foldingathome.service
      fi
    '';
  };
in
{
  options.custom.services.foldingathome = {
    enable = lib.mkEnableOption "Folding@home, gated on the current electricity price";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "JakeH";
      description = "Donor name credited with the completed work units.";
    };

    team = lib.mkOption {
      type = lib.types.int;
      default = 236565;
      description = "Team credited with the completed work units. Defaults to the NixOS team.";
    };

    maxPriceIncVat = lib.mkOption {
      type = lib.types.number;
      default = 0;
      description = ''
        Fold only while the current unit rate in p/kWh including VAT is
        strictly below this. The default of 0 folds on negative rates only.
      '';
    };

    octopus = {
      productCode = lib.mkOption {
        type = lib.types.str;
        default = "AGILE-24-10-01";
        description = "Octopus Energy product code to read unit rates from.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "C";
        description = "Octopus Energy distribution region letter.";
      };
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra startup options for the Folding@home client.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.foldingathome = {
      enable = true;
      inherit (cfg) user team extraArgs;
      daemonNiceLevel = 19;
    };

    # The client execs cores it downloads into its state directory. systemd
    # mounts that directory noexec for DynamicUser services, which fails every
    # such exec with EACCES, so run as a fixed user instead.
    users.users.foldingathome = {
      isSystemUser = true;
      group = "foldingathome";
      uid = config.ids.uids.foldingathome;
    };
    users.groups.foldingathome.gid = config.ids.gids.foldingathome;

    systemd.services.foldingathome = {
      # Started and stopped by the price gate rather than at boot.
      wantedBy = lib.mkForce [ ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "foldingathome";
        Group = "foldingathome";
        ExecStartPost = lib.getExe unpause;
      };
    };

    systemd.services.foldingathome-price-gate = {
      description = "Start or stop Folding@home based on the current electricity price";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "foldingathome-price-gate";
        RuntimeDirectoryMode = "0700";
        ExecStart = lib.getExe priceGate;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    systemd.timers.foldingathome-price-gate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Agile rates change on the half hour.
        OnCalendar = "*:00/30:20";
        OnBootSec = "2m";
        AccuracySec = "1s";
        Unit = "foldingathome-price-gate.service";
      };
    };

    # Work unit progress is checkpointed here, so a reboot or a price swing
    # doesn't throw away partial work.
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/foldingathome" ];
  };
}
