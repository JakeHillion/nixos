{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.awtrix-octopus-agile;

  # 4×7 gold lightning bolt — clean repeating zigzag, no gaps.
  # Centered in the ~9 px icon area (same space as the fireworks logo).
  # AWTRIX `draw` expects [{"dp":[x,y,"#RRGGBB"]}, ...].
  dp = x: y: { dp = [ x y "#FFD700" ]; };
  lightningDraw = [
    #         col: 3 4 5 6
    (dp 5 0) # . . . X . . . .
    (dp 4 1)
    (dp 5 1) # . . . X X . . .
    (dp 3 2)
    (dp 4 2) # . . X X . . . .
    (dp 4 3)
    (dp 5 3) # . . . X X . . .
    (dp 5 4) # . . . . X . . .
    (dp 4 5)
    (dp 5 5) # . . . X X . . .
    (dp 3 6)
    (dp 4 6) # . . X X . . . .
  ];

  runScript = pkgs.writeShellApplication {
    name = "awtrix-octopus-agile";
    runtimeInputs = with pkgs; [ curl jq coreutils gawk ];
    text = ''
      set -euo pipefail
      : "''${RUNTIME_DIRECTORY:?}"

      AWTRIX_HOST=${lib.escapeShellArg cfg.awtrixHost}
      APP_NAME=${lib.escapeShellArg cfg.appName}
      PRODUCT_CODE="AGILE-24-10-01"
      TARIFF_CODE="E-1R-AGILE-24-10-01-C"
      API_BASE="https://api.octopus.energy/v1/products/$PRODUCT_CODE/electricity-tariffs/$TARIFF_CODE/standard-unit-rates"

      while true; do
        TODAY=$(date -u +%Y-%m-%d)
        PERIOD_FROM="$TODAY"T00:00:00Z
        PERIOD_TO="$TODAY"T23:59:59Z
        RESPONSE_FILE="$RUNTIME_DIRECTORY/rates.json"

        echo "Fetching rates for $TODAY ..."

        if ! curl -sSf -o "$RESPONSE_FILE" "$API_BASE/?period_from=$PERIOD_FROM&period_to=$PERIOD_TO"; then
          echo "Failed to fetch daily rates, retrying in 60s"
          sleep 60
          continue
        fi

        NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        RATE=$(jq -r --arg now "$NOW_ISO" '
          .results[] | select(.valid_from <= $now and .valid_to > $now) | .value_inc_vat
        ' "$RESPONSE_FILE" | head -n1)

        if [ -z "$RATE" ] || [ "$RATE" = "null" ]; then
          echo "No current rate in daily set, trying fallback ..."
          if ! curl -sSf -o "$RESPONSE_FILE" "$API_BASE/"; then
            echo "Fallback fetch failed, retrying in 60s"
            sleep 60
            continue
          fi
          RATE=$(jq -r --arg now "$NOW_ISO" '
            .results[] | select(.valid_from <= $now and .valid_to > $now) | .value_inc_vat
          ' "$RESPONSE_FILE" | head -n1)
        fi

        if [ -z "$RATE" ] || [ "$RATE" = "null" ]; then
          echo "No current rate found, retrying in 60s"
          sleep 60
          continue
        fi

        LABEL=$(awk -v r="$RATE" 'BEGIN { printf "%.1fp", r }')
        echo "Current rate: $LABEL"

        TEXT_WIDTH=$((''${#LABEL} * 4))
        TEXT_OFFSET=$((32 - TEXT_WIDTH))

        PAYLOAD=$(jq -nc \
          --arg text "$LABEL" \
          --argjson draw ${lib.escapeShellArg (builtins.toJSON lightningDraw)} \
          --argjson x "$TEXT_OFFSET" \
          '{ draw: ($draw + [{"dt": [$x, 2, $text, "#FFFFFF"]}]),
             lifetime: 2100, lifetimeMode: 0, duration: 5,
             pushIcon: 0, center: false, noScroll: true }')

        curl -sSf -X POST -H "Content-Type: application/json" \
          --data "$PAYLOAD" "http://$AWTRIX_HOST/api/custom?name=$APP_NAME"

        echo "Pushed to AWTRIX, sleeping until next half-hour boundary"

        NOW_EPOCH=$(date +%s)
        NEXT_HALF_HOUR=$(( (( NOW_EPOCH / 1800 ) + 1 ) * 1800 ))
        SLEEP_SECONDS=$(( NEXT_HALF_HOUR - NOW_EPOCH ))

        if [ "$SLEEP_SECONDS" -le 0 ]; then
          SLEEP_SECONDS=1
        fi

        sleep "$SLEEP_SECONDS"
      done
    '';
  };
in
{
  options.custom.services.awtrix-octopus-agile = {
    enable = lib.mkEnableOption "awtrix octopus agile electricity rate display";

    awtrixHost = lib.mkOption {
      type = lib.types.str;
      default = "10.239.19.13";
      description = "Hostname or IP of the AWTRIX device.";
    };

    appName = lib.mkOption {
      type = lib.types.str;
      default = "octopus-agile";
      description = "AWTRIX custom app slot name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.awtrix-octopus-agile = {
      description = "Push current Octopus Agile electricity rate to AWTRIX display";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        RuntimeDirectory = "awtrix-octopus-agile";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "10s";
        ExecStart = lib.getExe runScript;
      };
    };
  };
}
