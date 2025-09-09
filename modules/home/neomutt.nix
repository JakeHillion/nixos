{ config, lib, pkgs, ... }:
let
  # Centralized configuration
  realName = "Jake Hillion";
  primaryAccount = "personal";

  # Mail directory - use persistent location if impermanence is enabled
  mailDir =
    if config.custom.impermanence.enable
    then "~/local/mail"
    else "~/.mail";

  maildirBasePath =
    if config.custom.impermanence.enable
    then "${config.custom.impermanence.base}/users/jake/mail"
    else "/home/jake/.mail";
in
{
  options.custom.home.neomutt = {
    enable = lib.mkEnableOption "neomutt email client with OfflineIMAP";

    backup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable backups to restic";
    };
  };

  config = lib.mkIf config.custom.home.neomutt.enable {
    # Configure agenix secret for SMTP password
    age.secrets.smtp-password = {
      file = ../../secrets/home/smtp-password.age;
      mode = "400";
      owner = config.custom.user;
    };

    # Configure restic backup secret
    age.secrets."restic/neomutt/mig29.key" = lib.mkIf config.custom.home.neomutt.backup {
      file = ../../secrets/restic/mig29.age;
      owner = config.custom.user;
    };
    home-manager.users.jake = {
      accounts.email = {
        maildirBasePath = maildirBasePath;
        accounts.personal = {
          realName = realName;
          address = "jake@hillion.co.uk";
          userName = "jake@hillion.co.uk";
          primary = true;

          imap = {
            host = "127.0.0.1";
            port = config.custom.services.protonmail-bridge.imapPort;
            tls.enable = false;
          };

          smtp = {
            host = "smtp-auth.mythic-beasts.com";
            port = 587;
            tls = {
              enable = true;
              useStartTls = true;
            };
          };

          # SMTP password for sending mail
          passwordCommand = "cat ${config.age.secrets.smtp-password.path}";

          offlineimap = {
            enable = true;
            postSyncHookCommand = lib.mkIf config.custom.home.neomutt.backup ''
              ${pkgs.restic}/bin/restic \
                --repo rest:https://restic.${config.ogygia.domain}/mig29 \
                --password-file ${config.age.secrets."restic/neomutt/mig29.key".path} \
                backup ${maildirBasePath} \
                --retry-lock 30s'';
            extraConfig.account = {
              autorefresh = "1";
            };
            extraConfig.remote = {
              remotepasseval = "get_password_personal()";
              folderfilter = "lambda f: f != 'All Mail'";
              createfolders = "False";
            };
          };

          maildir = {
            path = "personal";
          };

          folders = {
            inbox = "INBOX";
            drafts = "Drafts";
            sent = "Sent";
            trash = "Trash";
          };

          neomutt = {
            enable = true;
            extraConfig = ''
              mailboxes `${pkgs.findutils}/bin/find ${maildirBasePath}/personal -maxdepth 1 -type d ! -name ".*" ! -name "personal" -exec basename {} \; | sed 's/^/+/' | tr '\n' ' '`
            '';
          };
        };
      };

      programs.offlineimap = {
        enable = true;
        pythonFile = ''
          import subprocess
          
          def get_password_personal():
              path = "${if config.custom.impermanence.enable then "${config.custom.impermanence.base}/users/jake/.config/protonmail-bridge/bridge-password" else "~/.config/protonmail-bridge/bridge-password"}"
              return subprocess.check_output(f"${pkgs.coreutils}/bin/cat {path}", shell=True).decode().strip()
        '';
        extraConfig.general = {
          metadata = if config.custom.impermanence.enable then "${config.custom.impermanence.base}/users/jake/.local/share/offlineimap" else "~/.local/share/offlineimap";
        };
      };

      systemd.user.services.offlineimap = {
        Unit = {
          Description = "OfflineIMAP email sync";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.offlineimap}/bin/offlineimap";
          Restart = "on-failure";
          RestartSec = "30s";
          WorkingDirectory = "%h";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      programs.neomutt = {
        enable = true;
        sidebar = {
          enable = true;
          width = 20;
          shortPath = true;
        };

        settings = {
          # SMTP settings
          smtp_url = "smtps://jake@hillion.co.uk@smtp-auth.mythic-beasts.com:587/";
          smtp_pass = "`cat ${config.age.secrets.smtp-password.path}`";

          # Folder names
          spoolfile = "+INBOX";

          # Sorting - newest first
          sort = "reverse-date-received";
        };

        extraConfig = ''
          # HTML email viewing with w3m
          alternative_order text/plain text/enriched text/html
          auto_view text/html

          # Define mailcap for HTML viewing
          set mailcap_path = ${pkgs.writeText "mailcap" ''
            text/html; ${lib.getExe pkgs.w3m} -I %{charset} -T text/html -dump; copiousoutput;
          ''}
        '';
      };

    };
  };
}
