{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.ogygia-nix-eval-fuzz;

  user = "ogygia-nix-eval-fuzz";
  stateDir = "/var/lib/${user}";
  mountDir = "${stateDir}/fuzzing";
in
{
  options.custom.services.ogygia-nix-eval-fuzz = {
    enable = lib.mkEnableOption "ogygia-nix-eval-fuzz";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.custom.syncthing.baseDir}/projects/ogygia-nix/ogygia-nix-eval/fuzzing";
      description = ''
        Directory owned by the fuzzer: corpus, findings and runs. It must give
        the service user rwX through access and default ACLs.
      '';
    };

    ref = lib.mkOption {
      type = lib.types.str;
      default = "HEAD";
      example = "refs/heads/my-branch";
      description = "Upstream ref whose latest commit is fuzzed.";
    };

    pollInterval = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Seconds between checks of the upstream ref.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user} = {
      uid = config.ids.uids.${user};
      group = user;
      isSystemUser = true;
      home = stateDir;
    };
    users.groups.${user}.gid = config.ids.gids.${user};

    systemd.services.ogygia-nix-eval-fuzz = {
      description = "Differential fuzzing of ogygia-nix-eval against Nix";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = with pkgs; [ coreutils git nix util-linux ];

      serviceConfig = {
        User = user;
        Group = user;

        StateDirectory = user;
        BindPaths = [ "${cfg.dataDir}:${mountDir}" ];
        WorkingDirectory = mountDir;

        Restart = "on-failure";
        RestartSec = "5min";

        Nice = 19;
        CPUWeight = "idle";
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        OOMScoreAdjust = 1000;

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };

      script = ''
        set -euo pipefail

        head_rev() {
          git ls-remote --exit-code https://github.com/JakeHillion/ogygia-nix ${lib.escapeShellArg cfg.ref} | head -n1 | cut -f1
        }

        build() {
          nix build --print-out-paths "github:JakeHillion/ogygia-nix/$1#ogygia-nix-eval-fuzz" --out-link "$STATE_DIRECTORY/$2"
        }

        # The fuzzer leads its own process group, which its -fork workers
        # join, so the whole of it can be signalled and waited for.
        start() {
          echo "fuzzing $rev ($fuzzer)"
          setsid "$fuzzer/bin/ogygia-nix-eval-fuzz" run . &
          fuzz=$!
        }

        # Findings must not be rechecked while anything is still fuzzing, so
        # return only once every process in the group has gone.
        stop() {
          kill -TERM -- "-$fuzz" 2>/dev/null || true
          for _ in $(seq 60); do
            kill -0 -- "-$fuzz" 2>/dev/null || break
            sleep 1
          done
          while kill -0 -- "-$fuzz" 2>/dev/null; do
            kill -KILL -- "-$fuzz" 2>/dev/null || true
            sleep 1
          done
          wait "$fuzz" 2>/dev/null || true
        }

        until rev=$(head_rev) && fuzzer=$(build "$rev" current); do
          sleep ${toString cfg.pollInterval}
        done
        start

        while true; do
          sleep ${toString cfg.pollInterval} &
          sleeper=$!
          status=0
          wait -n -p finished "$fuzz" "$sleeper" || status=$?

          if [ "$finished" = "$fuzz" ]; then
            kill "$sleeper" 2>/dev/null || true
            echo "fuzzer exited with status $status"
            stop
            sleep 60
            start
            continue
          fi

          # The revision is baked into the build, so any upstream commit is a
          # new fuzzer.
          new_rev=$(head_rev) || continue
          [ "$new_rev" = "$rev" ] && continue
          new_fuzzer=$(build "$new_rev" next) || continue
          echo "upstream moved to $new_rev"
          stop
          mv -T "$STATE_DIRECTORY/next" "$STATE_DIRECTORY/current"
          rev=$new_rev
          fuzzer=$new_fuzzer
          start
        done
      '';
    };
  };
}
