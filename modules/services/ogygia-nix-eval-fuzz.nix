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

      path = with pkgs; [ coreutils git nix ];

      serviceConfig = {
        User = user;
        Group = user;

        StateDirectory = user;
        BindPaths = [ "${cfg.dataDir}:${mountDir}" ];
        WorkingDirectory = mountDir;

        Restart = "always";
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

        flake=github:JakeHillion/ogygia-nix

        head_rev() {
          git ls-remote --exit-code https://github.com/JakeHillion/ogygia-nix ${lib.escapeShellArg cfg.ref} | head -n1 | cut -f1
        }

        build() {
          nix build --print-out-paths "$flake/$1#ogygia-nix-eval-fuzz" --out-link "$STATE_DIRECTORY/$2"
        }

        rev=$(head_rev)
        fuzzer=$(build "$rev" current)

        echo "fuzzing $rev ($fuzzer)"

        # The revision is baked into the build, so any upstream commit is a new
        # fuzzer. Build it first, then exit; Restart= starts it.
        main=$$
        (
          while sleep ${toString cfg.pollInterval}; do
            new_rev=$(head_rev) || continue
            [ "$new_rev" = "$rev" ] && continue
            build "$new_rev" next >/dev/null || continue
            echo "upstream moved to $new_rev, restarting"
            kill "$main"
            exit
          done
        ) &

        exec "$fuzzer/bin/ogygia-nix-eval-fuzz" run .
      '';
    };
  };
}
