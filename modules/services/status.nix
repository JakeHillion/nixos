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
  };

  config = lib.mkIf cfg.enable {
    systemd.services.status = {
      description = "Status service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "exec";
        DynamicUser = true;
        ExecStart = "${status-jakehillion-me.packages.${pkgs.system}.default}/bin/status-jakehillion-me --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = "5s";

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

    services.caddy.virtualHosts."status.neb.jakehillion.me" = {
      listenAddresses = [ "::1" config.custom.dns.nebula.ipv4 ];
      extraConfig = ''
        tls {
          ca https://ca.neb.jakehillion.me:8443/acme/acme/directory
        }

        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };
  };
}
