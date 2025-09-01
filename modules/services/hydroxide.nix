{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.hydroxide;

  hydroxidectl = pkgs.writeScriptBin "hydroxidectl" ''
    #! ${pkgs.runtimeShell}
    set -e
    exec sudo ${pkgs.systemd}/bin/systemd-run \
      --pty --wait --collect --quiet \
      -p User=hydroxide \
      -p DynamicUser=yes \
      -p WorkingDirectory=/var/lib/hydroxide \
      -p StateDirectory=hydroxide \
      -p Environment=HOME=/var/lib/hydroxide \
      ${pkgs.hydroxide}/bin/hydroxide "$@"
  '';
in
{
  options.custom.services.hydroxide = {
    enable = lib.mkEnableOption "hydroxide";

    imapPort = lib.mkOption {
      type = lib.types.port;
      default = 15678;
      description = "IMAP server port";
    };

    smtpPort = lib.mkOption {
      type = lib.types.port;
      default = 12028;
      description = "SMTP server port";
    };

    carddavPort = lib.mkOption {
      type = lib.types.port;
      default = 8705;
      description = "CardDAV server port";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ hydroxidectl ];

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/hydroxide" ];

    systemd.services.hydroxide = {
      description = "Hydroxide ProtonMail Bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];
      wants = [ "network-online.target" ] ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "hydroxide";
        ExecStart = "${pkgs.hydroxide}/bin/hydroxide -imap-port ${toString cfg.imapPort} -smtp-port ${toString cfg.smtpPort} -carddav-port ${toString cfg.carddavPort} serve";
        Restart = "on-failure";
        RestartSec = 5;

        # Set HOME directory for hydroxide to find auth data
        Environment = "HOME=/var/lib/hydroxide";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
      };
    };
  };
}
