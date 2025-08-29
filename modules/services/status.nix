{ config, pkgs, lib, status-jakehillion-me, ... }:

let
  cfg = config.custom.services.status;
in
{
  options.custom.services.status = {
    enable = lib.mkEnableOption "status";

    port = lib.mkOption {
      type = lib.types.port;
      default = 47283;
      description = "Port for status service to listen on";
    };

    gitRemoteUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://gitea.hillion.co.uk/JakeHillion/nixos.git";
      description = "Git remote URL for the status service";
    };

  };

  config = lib.mkIf cfg.enable (
    let
      configFile = pkgs.writers.writeTOML "status-config.toml" {
        server = {
          port = cfg.port;
        };
        git = {
          remote_url = cfg.gitRemoteUrl;
        };
        zookeeper = {
          endpoints = config.custom.services.zookeeper.clientHosts;
        };
      };
    in
    {
      systemd.services.status = {
        description = "Status service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          RUST_LOG = "info";
        };

        serviceConfig = {
          Type = "exec";
          DynamicUser = true;
          ExecStart = "${status-jakehillion-me.packages.${pkgs.system}.default}/bin/status-jakehillion-me --config ${configFile}";
          Restart = "always";
          RestartSec = "1s";
          StartLimitIntervalSec = "60s";
          StartLimitBurst = "5";

          # Security
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
        };
      };

      services.caddy.virtualHosts."status.${config.ogygia.domain}" = {
        listenAddresses = [ "::1" config.custom.dns.nebula.ipv4 ];
        extraConfig = ''
          tls {
            ca https://ca.${config.ogygia.domain}:8443/acme/acme/directory
          }

          reverse_proxy http://127.0.0.1:${toString cfg.port}
        '';
      };
    }
  );
}
