{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.supos;

  profile = "/nix/var/nix/profiles/supos";
in
{
  options.custom.services.supos = {
    enable = lib.mkEnableOption "supos";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "supos.jakehillion.me";
      description = "Public domain supos is served from";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8095;
      description = "Local port for supos to listen on";
    };

    flake = lib.mkOption {
      type = lib.types.str;
      default = "git+ssh://git@ssh.gitea.hillion.co.uk/JakeHillion/supobot.git?ref=main#supos";
      description = "Flake reference built into the supos profile";
    };

    supervisors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "jsh77" ];
      description = "CRSids of supervisors";
    };

    oidcClientId = lib.mkOption {
      type = lib.types.str;
      default = "8c2f5e70-71d2-4320-8a4f-8f7adc21d86e";
      description = "OIDC client ID of the UIS Toolkit application registration";
    };

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "supos/oidc-client-secret".rekeyFile = ./oidc-client-secret.age;

      "backups/supos/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../../secrets/restic/mig29.age;
      };
    };

    custom.impermanence.extraDirs = lib.mkIf config.custom.impermanence.enable
      [ "/var/lib/supos-update" ];

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "supos" ];
      ensureUsers = [{
        name = "supos";
        ensureDBOwnership = true;
      }];
    };

    # supos is closed source, so it can't be an input of this flake. Build it
    # on this host into a profile with a deploy key and run it from there. The
    # key is generated on first run; add the printed public key to the repo as
    # a read-only deploy key.
    systemd.services.supos-update = {
      description = "Build supos into its profile";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ config.nix.package pkgs.git pkgs.openssh ];

      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "supos-update";
        StateDirectoryMode = "0700";
      };

      script = ''
        set -euo pipefail

        key="$STATE_DIRECTORY/deploy-key"
        if [ ! -f "$key" ]; then
          ssh-keygen -q -t ed25519 -N "" -C "supos-update@${config.networking.fqdn}" -f "$key"
        fi
        echo "deploy key: $(cat "$key.pub")"

        export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes"

        before=$(readlink -f ${profile} || true)
        nix build --refresh --profile ${profile} ${lib.escapeShellArg cfg.flake}
        after=$(readlink -f ${profile})

        if [ "$before" != "$after" ]; then
          echo "supos updated to $after"
          systemctl restart supos.service
        fi
      '';
    };

    systemd.timers.supos-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = "1h";
        RandomizedDelaySec = "5m";
      };
    };

    systemd.services.supos = {
      description = "supos supervision scheduling server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.target" ];
      requires = [ "postgresql.target" ];
      unitConfig.ConditionPathExists = profile;

      serviceConfig = {
        DynamicUser = true;
        User = "supos";
        Group = "supos";
        LoadCredential = "oidc-client-secret:${config.age.secrets."supos/oidc-client-secret".path}";

        ExecStart = lib.escapeShellArgs ([
          "${profile}/bin/supos"
          "--listen"
          "127.0.0.1:${toString cfg.port}"
          "--database-url"
          "postgres:///supos?host=/run/postgresql&user=supos"
          "--public-url"
          "https://${cfg.domain}"
          "--oidc-client-id"
          cfg.oidcClientId
          "--oidc-client-secret-file"
          "%d/oidc-client-secret"
        ]
        ++ lib.concatMap (s: [ "--supervisor" s ]) cfg.supervisors);

        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts.${cfg.domain}.extraConfig = ''
        encode gzip zstd
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    services.postgresqlBackup = lib.mkIf cfg.backup {
      enable = true;
      compression = "none"; # for better diffing
      databases = [ "supos" ];
    };

    services.restic.backups."supos" = lib.mkIf cfg.backup {
      user = "root";
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "60m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/supos/restic/mig29".path;
      paths = [
        "${config.services.postgresqlBackup.location}/supos.sql"
      ];
    };
  };
}
