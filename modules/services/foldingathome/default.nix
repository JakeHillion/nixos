{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.foldingathome;

  tariffCode = "E-1R-${cfg.octopus.productCode}-${cfg.octopus.region}";

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

    # Started and stopped by the price gate rather than at boot.
    systemd.services.foldingathome.wantedBy = lib.mkForce [ ];

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
    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/foldingathome" ];
  };
}
