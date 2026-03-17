{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.gitea.actions;
in
{
  options.custom.services.gitea.actions = {
    enable = lib.mkEnableOption "gitea-actions";

    labels = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "ubuntu-latest:docker://node:22-bookworm"
        "ubuntu-22.04:docker://node:22-bookworm"
        "ubuntu-24.04:docker://node:22-bookworm"
      ];
    };
    tokenSecret = lib.mkOption {
      type = lib.types.path;
    };
    dockerDataPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    capacity = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Number of concurrent jobs the runner will accept.";
    };
    nixBuildCores = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 4;
      description = "Number of cores each Nix build job may use inside CI containers. Sets NIX_BUILD_CORES via Docker environment variable.";
    };
    dockerMemoryHigh = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 8589934592;
      description = "Per-Docker-container memory.high cgroup v2 soft limit in bytes. Applied via custom runc wrapper since Docker has no native support for memory.high.";
    };
  };

  config = lib.mkIf cfg.enable {
    custom.services.gitea.actions.dockerDataPath = lib.mkIf config.custom.impermanence.cache.enable
      (lib.mkOverride 999 "${config.custom.impermanence.cache.path}/system/gitea-actions-docker");

    systemd.tmpfiles.rules = lib.optionals (cfg.dockerDataPath != null) [
      "d ${cfg.dockerDataPath} 0700 root root - -"
    ];

    age.secrets."gitea/actions/token".file = cfg.tokenSecret;

    # Run gitea-actions in a container and firewall it such that it can only
    # access the Internet (not private networks).
    containers."gitea-actions" = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true; # all traffic goes through ve-gitea-actions on the host
      hostAddress = "10.108.27.1";
      localAddress = "10.108.27.2";

      extraFlags = [
        # Extra system calls required to nest Docker, taken from https://wiki.archlinux.org/title/systemd-nspawn
        "--system-call-filter=add_key"
        "--system-call-filter=keyctl"
        "--system-call-filter=bpf"
      ];

      bindMounts = let tokenPath = config.age.secrets."gitea/actions/token".path; in {
        "${tokenPath}".hostPath = tokenPath;
      } // lib.optionalAttrs (cfg.dockerDataPath != null) {
        "/var/lib/docker" = { hostPath = cfg.dockerDataPath; isReadOnly = false; };
      };

      timeoutStartSec = "5min";

      config = (hostConfig: ({ config, pkgs, ... }: {
        config =
          let
            cfg = hostConfig.custom.services.gitea.actions;

            # Wrapper around runc that injects memory.high into the OCI config.
            # Docker has no native support for cgroup v2 memory.high
            # (https://github.com/moby/moby/issues/49599), so we intercept
            # container creation and set it via the OCI unified cgroup field.
            runcWrapper = pkgs.writeShellScript "runc-memory-high" ''
              bundle=""
              is_create=0
              prev=""
              for arg in "$@"; do
                case "$arg" in
                  create|run) is_create=1 ;;
                esac
                if [ "$prev" = "--bundle" ] || [ "$prev" = "-b" ]; then
                  bundle="$arg"
                fi
                prev="$arg"
              done

              if [ "$is_create" = "1" ] && [ -n "$bundle" ] && [ -f "$bundle/config.json" ]; then
                ${pkgs.jq}/bin/jq --arg mh "${toString cfg.dockerMemoryHigh}" \
                  '.linux.resources.unified["memory.high"] = $mh' \
                  "$bundle/config.json" > "$bundle/config.json.tmp" && \
                  mv "$bundle/config.json.tmp" "$bundle/config.json"
              fi

              exec ${pkgs.runc}/bin/runc "$@"
            '';
          in
          {
            system.stateVersion = "23.11";

            virtualisation.docker.enable = true;
            virtualisation.docker.daemon.settings = lib.mkIf (cfg.dockerMemoryHigh != null) {
              runtimes."runc-memlimit".path = "${runcWrapper}";
              "default-runtime" = "runc-memlimit";
            };

            services.gitea-actions-runner.instances.container = {
              enable = true;
              url = "https://gitea.hillion.co.uk";
              tokenFile = hostConfig.age.secrets."gitea/actions/token".path;

              name = "${hostConfig.networking.hostName}";
              labels = cfg.labels;

              settings = {
                runner = {
                  capacity = cfg.capacity;
                };
                container = {
                  options = lib.concatStringsSep " " (
                    lib.optional (cfg.nixBuildCores != null) "--env NIX_BUILD_CORES=${toString cfg.nixBuildCores}"
                  );
                };
                cache = {
                  enabled = true;
                  host = "10.108.27.2";
                  port = 41919;
                };
              };
            };

            # Drop any packets to private networks
            networking = {
              firewall.enable = lib.mkForce false;
              nftables = {
                enable = true;
                ruleset = ''
                  table inet filter {
                    chain output {
                      type filter hook output priority 100; policy accept;

                      ct state { established, related } counter accept

                      ip daddr 10.0.0.0/8 drop
                      ip daddr 100.64.0.0/10 drop
                      ip daddr 172.16.0.0/12 drop
                      ip daddr 192.168.0.0/16 drop
                    }
                  }
                '';
              };
            };
          };
      })) config;
    };

    networking.nat = {
      enable = true;
      externalInterface = "eth0";
      internalIPs = [ "10.108.27.2" ];
    };
  };
}
