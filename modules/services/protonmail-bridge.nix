{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.protonmail-bridge;

  protonmail-bridgectl = pkgs.writeScriptBin "protonmail-bridgectl" ''
    #! ${pkgs.runtimeShell}
    set -e

    # Ensure service is restarted on exit
    trap 'echo "Starting protonmail-bridge service..."; sudo ${pkgs.systemd}/bin/systemctl start protonmail-bridge.service' EXIT

    echo "Stopping protonmail-bridge service..."
    sudo ${pkgs.systemd}/bin/systemctl stop protonmail-bridge.service

    echo "Starting ProtonMail Bridge CLI..."
    sudo ${pkgs.systemd}/bin/systemd-run \
      --pty --wait --collect --quiet \
      -p User=protonmail-bridge \
      -p DynamicUser=yes \
      -p WorkingDirectory=/var/lib/protonmail-bridge \
      -p StateDirectory=protonmail-bridge \
      -p Environment=HOME=/var/lib/protonmail-bridge \
      -p Environment=PATH="${lib.makeBinPath [ pkgs.gnupg pkgs.pass pkgs.coreutils pkgs.protonmail-bridge ]}" \
      ${pkgs.protonmail-bridge}/bin/protonmail-bridge --cli
  '';

in
{
  options.custom.services.protonmail-bridge = {
    enable = lib.mkEnableOption "protonmail-bridge";

    imapPort = lib.mkOption {
      type = lib.types.port;
      default = 1143;
      readOnly = true;
      description = "IMAP server port (ProtonMail Bridge default)";
    };

    smtpPort = lib.mkOption {
      type = lib.types.port;
      default = 1025;
      readOnly = true;
      description = "SMTP server port (ProtonMail Bridge default)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ protonmail-bridgectl ];

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable [ "/var/lib/private/protonmail-bridge" ];


    systemd.services.protonmail-bridge = {
      description = "ProtonMail Bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];
      wants = [ "network-online.target" ] ++ lib.optionals config.custom.impermanence.enable [ "fix-var-lib-private-permissions.service" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "protonmail-bridge";

        ExecStartPre = pkgs.writeShellScript "protonmail-bridge-setup" ''
          set -euo pipefail

          # Create GPG key if it doesn't exist
          if ! ${pkgs.gnupg}/bin/gpg --list-keys "ProtonMail Bridge" 2>/dev/null; then
            ${pkgs.gnupg}/bin/gpg --batch --passphrase "" --quick-gen-key "ProtonMail Bridge" default default never
          fi

          # Initialize pass if not already initialized
          if ! test -d .password-store; then
            ${pkgs.pass}/bin/pass init "ProtonMail Bridge"
          fi
        '';
        ExecStart = pkgs.writeShellScript "protonmail-bridge-wrapper" ''
          set -euo pipefail
          export PATH="${lib.makeBinPath [ pkgs.gnupg pkgs.pass pkgs.coreutils pkgs.protonmail-bridge ]}"
          exec ${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive
        '';

        Restart = "on-failure";
        RestartSec = 5;

        # Set HOME directory for protonmail-bridge to find auth data
        Environment = "HOME=/var/lib/protonmail-bridge";

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
