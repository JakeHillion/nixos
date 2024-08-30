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
        "ubuntu-latest:docker://node:16-bullseye"
        "ubuntu-20.04:docker://node:16-bullseye"
      ];
    };
    tokenSecret = lib.mkOption {
      type = lib.types.path;
    };
  };

  config = lib.mkIf cfg.enable {
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
      };

      timeoutStartSec = "5min";

      config = (hostConfig: ({ config, pkgs, ... }: {
        config = let cfg = hostConfig.custom.services.gitea.actions; in {
          system.stateVersion = "23.11";

          virtualisation.docker.enable = true;

          services.gitea-actions-runner.instances.container = {
            enable = true;
            url = "https://gitea.hillion.co.uk";
            tokenFile = hostConfig.age.secrets."gitea/actions/token".path;

            name = "${hostConfig.networking.hostName}";
            labels = cfg.labels;

            settings = {
              runner = {
                capacity = 3;
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
