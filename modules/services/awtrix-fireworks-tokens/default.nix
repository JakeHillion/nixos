{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.awtrix-fireworks-tokens;

  # 9x8 rendering of the Fireworks.AI favicon, downsampled from the 32x32
  # variant of https://fireworks.ai/favicon.ico (trim -> resize 9x8 ->
  # alpha threshold 35%). AWTRIX `draw` wants the shape
  # `[{"dp":[x,y,"#RRGGBB"]}, ...]`.
  dp = x: y: { dp = [ x y fireworksPurple ]; };
  fireworksPurple = "#5F25F5";
  logoDraw = [
    #         col: 0 1 2 3 4 5 6 7 8
    (dp 3 0)
    (dp 5 0) # . . . X . X . . .
    (dp 3 1)
    (dp 5 1) # . . . X . X . . .
    (dp 3 2)
    (dp 5 2) # . . . X . X . . .
    (dp 1 3)
    (dp 3 3)
    (dp 4 3)
    (dp 5 3)
    (dp 7 3) # . X . X X X . X .
    (dp 1 4)
    (dp 2 4)
    (dp 4 4)
    (dp 6 4)
    (dp 7 4) # . X X . X . X X .
    (dp 2 5)
    (dp 6 5) # . . X . . . X . .
    (dp 2 6)
    (dp 3 6)
    (dp 5 6)
    (dp 6 6) # . . X X . X X . .
    (dp 0 7)
    (dp 1 7)
    (dp 2 7)
    (dp 3 7)
    (dp 5 7)
    (dp 6 7)
    (dp 7 7)
    (dp 8 7) # X X X X . X X X X
  ];

  runScript = pkgs.writeShellApplication {
    name = "awtrix-fireworks-tokens";
    runtimeInputs = with pkgs; [ firectl curl jq coreutils gawk ];
    text = ''
      set -euo pipefail
      : "''${CREDENTIALS_DIRECTORY:?}"
      : "''${RUNTIME_DIRECTORY:?}"

      # firectl reads/writes ~/.config/fireworks; with DynamicUser there is no
      # real $HOME, so point it at the per-invocation runtime directory.
      export HOME="$RUNTIME_DIRECTORY"

      FIREWORKS_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/fireworks-api-key")
      ACCOUNT_ID=${lib.escapeShellArg cfg.accountId}
      MODEL=${lib.escapeShellArg cfg.model}
      AWTRIX_HOST=${lib.escapeShellArg cfg.awtrixHost}
      APP_NAME=${lib.escapeShellArg cfg.appName}

      END=$(date -u +%Y-%m-%d)
      START=$(date -u -d "7 days ago" +%Y-%m-%d)
      CSV="$RUNTIME_DIRECTORY/billing.csv"
      rm -f "$CSV"

      firectl -a "$ACCOUNT_ID" --api-key "$FIREWORKS_API_KEY" \
        billing export-metrics \
        --start-time "$START" --end-time "$END" --filename "$CSV"

      # CSV columns: email,start_time,end_time,usage_type,accelerator_type,
      #   accelerator_seconds,base_model_name,model_bucket,parameter_count,
      #   prompt_tokens,completion_tokens
      TOTAL=$(awk -F, -v model="$MODEL" '
        NR==1 { next }
        index($7, model) > 0 {
          p = ($10=="" ? 0 : $10); c = ($11=="" ? 0 : $11); sum += p + c
        }
        END { printf "%d", (sum ? sum : 0) }
      ' "$CSV")

      echo "fireworks 7-day token total for $MODEL: $TOTAL"

      URL="http://$AWTRIX_HOST/api/custom?name=$APP_NAME"

      if [ "$TOTAL" -le 0 ]; then
        curl -sSf -X POST -H "Content-Type: application/json" --data "" "$URL"
        exit 0
      fi

      LABEL=$(awk -v n="$TOTAL" 'BEGIN {
        if (n >= 1000000000) printf "%dB", n/1000000000
        else if (n >= 1000000) printf "%dM", n/1000000
        else if (n >= 1000) printf "%dK", n/1000
        else printf "%d", n
      }')

      PAYLOAD=$(jq -nc \
        --arg text "$LABEL" \
        --argjson draw ${lib.escapeShellArg (builtins.toJSON logoDraw)} \
        '{ text: $text, textOffset: 10, draw: $draw,
           lifetime: 5400, lifetimeMode: 0, duration: 5,
           pushIcon: 0, center: false, noScroll: true }')

      curl -sSf -X POST -H "Content-Type: application/json" \
        --data "$PAYLOAD" "$URL"
    '';
  };
in
{
  options.custom.services.awtrix-fireworks-tokens = {
    enable = lib.mkEnableOption "awtrix fireworks token counter";

    awtrixHost = lib.mkOption {
      type = lib.types.str;
      default = "10.239.19.13";
      description = "Hostname or IP of the AWTRIX device.";
    };

    accountId = lib.mkOption {
      type = lib.types.str;
      default = "jakehillion";
      description = "Fireworks.AI account ID.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "kimi-k2p5";
      description = "Model name substring to match in the billing CSV.";
    };

    appName = lib.mkOption {
      type = lib.types.str;
      default = "fireworks-tokens";
      description = "AWTRIX custom app slot name.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."awtrix-fireworks-tokens/api-key".rekeyFile = ./api-key.age;

    systemd.services.awtrix-fireworks-tokens = {
      description = "Update AWTRIX custom app with Fireworks 7-day token usage";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        RuntimeDirectory = "awtrix-fireworks-tokens";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [
          "fireworks-api-key:${config.age.secrets."awtrix-fireworks-tokens/api-key".path}"
        ];
        ExecStart = lib.getExe runScript;
      };
    };

    systemd.timers.awtrix-fireworks-tokens = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "2m";
        Unit = "awtrix-fireworks-tokens.service";
      };
    };
  };
}
