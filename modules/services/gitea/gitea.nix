{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.gitea;
in
{
  options.custom.services.gitea = {
    enable = lib.mkEnableOption "gitea";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };
    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 3022;
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "gitea/mailer_password" = {
        file = ../../../secrets/gitea/mailer_password.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
      };
      "gitea/oauth_jwt_secret" = {
        file = ../../../secrets/gitea/oauth_jwt_secret.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/oauth2_jwt_secret";
      };
      "gitea/lfs_jwt_secret" = {
        file = ../../../secrets/gitea/lfs_jwt_secret.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/lfs_jwt_secret";
      };
      "gitea/security_secret_key" = {
        file = ../../../secrets/gitea/security_secret_key.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/secret_key";
      };
      "gitea/security_internal_token" = {
        file = ../../../secrets/gitea/security_internal_token.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/internal_token";
      };
    };

    users.users.gitea.uid = config.ids.uids.gitea;
    users.groups.gitea.gid = config.ids.gids.gitea;

    services.gitea = {
      enable = true;
      package = pkgs.unstable.gitea;
      mailerPasswordFile = config.age.secrets."gitea/mailer_password".path;

      appName = "Hillion Gitea";

      database = {
        type = "sqlite3";
        name = "gitea";
        path = "${config.services.gitea.stateDir}/data/gitea.db";
      };
      lfs.enable = true;

      settings = {
        server = {
          DOMAIN = "gitea.hillion.co.uk";
          HTTP_PORT = cfg.httpPort;
          ROOT_URL = "https://gitea.hillion.co.uk/";
          OFFLINE_MODE = false;
          START_SSH_SERVER = true;
          SSH_LISTEN_PORT = cfg.sshPort;
          BUILTIN_SSH_SERVER_USER = "git";
          SSH_DOMAIN = "ssh.gitea.hillion.co.uk";
          SSH_PORT = 22;
        };

        mailer = {
          ENABLED = true;
          SMTP_ADDR = "smtp.mailgun.org:587";
          FROM = "gitea@mg.hillion.co.uk";
          USER = "gitea@mg.hillion.co.uk";
        };
        security = {
          INSTALL_LOCK = true;
        };
        service = {
          REGISTER_EMAIL_CONFIRM = true;
          ENABLE_NOTIFY_MAIL = true;
          EMAIL_DOMAIN_ALLOWLIST = "hillion.co.uk,cam.ac.uk,cl.cam.ac.uk";
        };
        session = {
          PROVIDER = "file";
        };
        "cron.archive_cleanup" = {
          ENABLED = true;
          SCHEDULE = "@midnight";
          OLDER_THAN = "28d";
        };
      };
    };

    # Swap cfg.sshPort and port 22 on eth0
    networking.firewall.extraCommands = ''
      # proxy all traffic on public interface to the gitea SSH server
      iptables  -A PREROUTING -t nat -i eth0 -p tcp --dport 22 -j REDIRECT --to-port ${builtins.toString cfg.sshPort}
      ip6tables -A PREROUTING -t nat -i eth0 -p tcp --dport 22 -j REDIRECT --to-port ${builtins.toString cfg.sshPort}
      iptables  -A PREROUTING -t nat -i eth0 -p tcp --dport ${builtins.toString cfg.sshPort} -j REDIRECT --to-port 22
      ip6tables -A PREROUTING -t nat -i eth0 -p tcp --dport ${builtins.toString cfg.sshPort} -j REDIRECT --to-port 22

      # proxy locally originating outgoing packets
      iptables  -A OUTPUT -d 138.201.252.214      -t nat -p tcp --dport 22 -j REDIRECT --to-port ${builtins.toString cfg.sshPort}
      ip6tables -A OUTPUT -d 2a01:4f8:173:23d2::2 -t nat -p tcp --dport 22 -j REDIRECT --to-port ${builtins.toString cfg.sshPort}
    '';
  };
}
