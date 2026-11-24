{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.foldingathome;

  # fah-client ships "paused": true in the default resource group
  # (src/resources/group.json) and registers no option to change it, so a fresh
  # client sits idle until something tells it to fold. GPUs are held back the
  # same way: Config::isGPUEnabled reports any GPU missing from the group's
  # gpus dict as disabled, and that dict also starts out empty. Its HTTP server
  # exposes a single route, a websocket; everything else redirects to the
  # hosted Web Control. Both commands are idempotent, and the state they leave
  # behind is written to client.db.
  configure = pkgs.writeShellApplication {
    name = "foldingathome-configure";
    runtimeInputs = with pkgs; [ coreutils ] ++ lib.optionals cfg.gpu.enable [ jq ];
    text = ''
      set -euo pipefail
      export LC_ALL=C

      # Leaves the socket on fd 3, positioned at the first websocket frame.
      open() {
        local attempt line

        for attempt in $(seq 60); do
          if exec 3<>/dev/tcp/127.0.0.1/7396; then break; fi
          if [ "$attempt" = 60 ]; then
            echo "timed out waiting for the client to start listening" >&2
            exit 1
          fi
          sleep 1
        done

        printf 'GET /api/websocket HTTP/1.1\r\nHost: 127.0.0.1:7396\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\nSec-WebSocket-Version: 13\r\n\r\n' >&3

        read -r line <&3
        case "$line" in
          *101*) ;;
          *) echo "unexpected handshake response: $line" >&2; exit 1 ;;
        esac

        while read -r line <&3; do
          [ "$line" = $'\r' ] && break
        done
      }

      send() {
        local payload="$1"
        local length=''${#payload}
        local header

        if [ "$length" -lt 126 ]; then
          header="\x81\x$(printf '%02x' $((0x80 | length)))"
        else
          header="\x81\xfe\x$(printf '%02x' $((length >> 8)))\x$(printf '%02x' $((length & 0xff)))"
        fi

        # Client frames must be masked, but an all zero key leaves the payload as is.
        printf '%b%s' "$header\x00\x00\x00\x00" "$payload" >&3
      }

      ${lib.optionalString cfg.gpu.enable ''
        byte() { dd bs=1 count=1 status=none <&3 | od -An -tu1 | tr -d ' \n'; }

        # The client greets every new connection with its whole state as one
        # text frame. Server frames carry no mask, so the payload follows the
        # length directly.
        readState() {
          local opcode length high low

          opcode=$(byte)
          if [ "$opcode" != 129 ]; then
            echo "unexpected websocket opcode $opcode" >&2
            exit 1
          fi

          length=$(byte)
          if [ "$length" = 126 ]; then
            high=$(byte)
            low=$(byte)
            length=$((high * 256 + low))
          elif [ "$length" = 127 ]; then
            echo "state frame is implausibly large" >&2
            exit 1
          fi

          head -c "$length" <&3
        }

        # Enable only the GPUs the client itself calls supported, which means it
        # found both a compute device and a species for them in the Folding@home
        # database. Enabling anything else wedges the group rather than being
        # ignored: Group::waitOnGPU holds off every work unit request, CPU ones
        # included, for as long as an enabled GPU is missing from that list.
        gpus=()
        for attempt in $(seq 15); do
          open
          mapfile -t gpus < <(readState | jq -r '(.info.gpus // {}) | to_entries[] | select(.value.supported) | .key')
          exec 3>&-

          [ ''${#gpus[@]} -gt 0 ] && break

          # Detection waits on the GPU database, fetched on the first run.
          echo "attempt $attempt: no supported GPU yet"
          sleep 1
        done

        echo "enabling GPUs: ''${gpus[*]:-none found}"
      ''}
      open
      ${lib.optionalString cfg.gpu.enable ''
        # Naming the default group drops every other resource group, which is
        # fine as long as nothing else creates any.
        send "$(jq -cn --args '{
          cmd: "config",
          config: {
            groups: {
              "": {gpus: ($ARGS.positional | map({(.): {enabled: true}}) | add // {})}
            }
          }
        }' "''${gpus[@]}")"
      ''}
      send '{"cmd":"state","state":"fold"}'
    '';
  };

  scheduled = "/run/systemd/shutdown/scheduled";

  # Home Assistant keeps a poweroff scheduled half an hour out for as long as
  # it wants heat, so a host it loses track of turns itself off. Cancelling
  # the poweroff hands the host back.
  fold = pkgs.writeShellApplication {
    name = "fold";
    text = ''
      case "''${SSH_ORIGINAL_COMMAND:-}" in
        fold-schedule-poweroff)
          /run/wrappers/bin/sudo ${shutdown} +30
          [ -e ${scheduled} ]
          ;;
        fold-poweroff-status)
          if [ -e ${scheduled} ]; then
            echo scheduled
          else
            echo none
          fi
          ;;
        *)
          echo "unknown command: ''${SSH_ORIGINAL_COMMAND:-}" >&2
          exit 1
          ;;
      esac
    '';
  };

  shutdown = "${config.systemd.package}/bin/shutdown";

  gate = pkgs.writeShellApplication {
    name = "foldingathome-gate";
    runtimeInputs = with pkgs; [ curl jq systemd ];
    text = ''
      URL="http://${config.custom.locations.locations.services.homeassistant}:8123/api/states/binary_sensor.fold_wanted"
      TOKEN_FILE=${lib.escapeShellArg config.age.secrets."foldingathome/homeassistant-token".path}

      STATE=""
      for attempt in 1 2 3; do
        if STATE=$(curl -sSf --max-time 10 -H @- "$URL" < <(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") | jq -r .state); then
          break
        fi
        STATE=""
        echo "attempt $attempt: could not read binary_sensor.fold_wanted"
        sleep 5
      done

      case "$STATE" in
        on)
          echo "fold_wanted is on, folding"
          systemctl start foldingathome.service
          ;;
        off)
          echo "fold_wanted is off, not folding"
          systemctl stop foldingathome.service
          ;;
        *)
          # Fail closed: without an answer, assume heat isn't wanted.
          echo "fold_wanted is ''${STATE:-unknown}, stopping folding"
          systemctl stop foldingathome.service
          exit 1
          ;;
      esac
    '';
  };

  homeAssistantKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILkF8H7Vyf5/YQlU2ukCUIGe7rPjM45z7OtWtAUbzWG4 hass@stinger";
in
{
  options.custom.services.foldingathome = {
    enable = lib.mkEnableOption "Folding@home, run while Home Assistant wants heat";

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

    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Fold on this host's GPUs as well as its CPUs. The compute runtime
        provided is ROCm's OpenCL, so only AMD GPUs are covered.
      '';
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
      # render owns /dev/kfd and the DRM render nodes, which ROCm's OpenCL
      # needs to reach the GPU.
      extraGroups = lib.optional cfg.gpu.enable "render";
    };
    users.groups.foldingathome.gid = config.ids.gids.foldingathome;

    # fahclient is an FHS environment carrying the ocl-icd loader, which reads
    # its vendor list from /run/opengl-driver/etc/OpenCL/vendors.
    hardware.graphics = lib.mkIf cfg.gpu.enable {
      enable = true;
      extraPackages = [ pkgs.rocmPackages.clr.icd ];
    };

    systemd.services.foldingathome = {
      # Started and stopped by the gate rather than at boot.
      wantedBy = lib.mkForce [ ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "foldingathome";
        Group = "foldingathome";
        ExecStartPost = lib.getExe configure;
      };
    };

    users.users.fold = {
      isSystemUser = true;
      group = "fold";
      # sshd runs the forced command through the login shell.
      useDefaultShell = true;
      openssh.authorizedKeys.keys = [ ''command="${lib.getExe fold}",restrict ${homeAssistantKey}'' ];
    };
    users.groups.fold = { };

    security.sudo.extraRules = [{
      users = [ "fold" ];
      commands = [{
        command = "${shutdown} +30";
        options = [ "NOPASSWD" ];
      }];
    }];

    age.secrets."foldingathome/homeassistant-token".rekeyFile = ./homeassistant-token.age;

    systemd.services.foldingathome-gate = {
      description = "Start or stop Folding@home as Home Assistant wants heat";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe gate;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    systemd.timers.foldingathome-gate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
        OnBootSec = "1m";
        Unit = "foldingathome-gate.service";
      };
    };

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/foldingathome" ];
  };
}
