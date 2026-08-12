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
    services.gitea.stateDir = lib.mkIf config.custom.impermanence.enable "${config.custom.impermanence.base}/system/var/lib/gitea";

    age.secrets = {
      "gitea/mailer_password" = {
        file = ./mailer_password.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
      };
      "gitea/oauth_jwt_secret" = {
        file = ./oauth_jwt_secret.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/oauth2_jwt_secret";
      };
      "gitea/lfs_jwt_secret" = {
        file = ./lfs_jwt_secret.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/lfs_jwt_secret";
      };
      "gitea/security_secret_key" = {
        file = ./security_secret_key.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/secret_key";
      };
      "gitea/security_internal_token" = {
        file = ./security_internal_token.age;
        owner = config.services.gitea.user;
        group = config.services.gitea.group;
        path = "${config.services.gitea.customDir}/conf/internal_token";
      };
    };

    users.users.gitea.uid = config.ids.uids.gitea;
    users.groups.gitea.gid = config.ids.gids.gitea;

    services.anubis.instances.gitea = {
      settings = {
        BIND = "${config.custom.dns.nebula.ipv4}:8923";
        BIND_NETWORK = "tcp";
        METRICS_BIND = "127.0.0.1:8924";
        METRICS_BIND_NETWORK = "tcp";
        TARGET = "http://127.0.0.1:${toString cfg.httpPort}";
        DIFFICULTY = 4;
        OG_PASSTHROUGH = true;
        WEBMASTER_EMAIL = "jake@hillion.co.uk";
      };
      # A custom botPolicy replaces Anubis' baked-in policy wholesale (the module
      # does not merge the two), so re-import the upstream default set and layer
      # one rule on top. Anubis' own headless-browser rule anchors on the string
      # "LightPanda", but the scraper hammering us identifies as "Lightpanda/1.0",
      # so that rule never matches and the bot is served in full. Match the
      # user-agent case-insensitively and weigh it into the proof-of-work
      # challenge tier: it arrives from thousands of cookie-less IPs, so a
      # challenge it never carries forward is enough to keep it off the backend.
      botPolicy = {
        bots = [
          {
            name = "lightpanda";
            user_agent_regex = "(?i)^lightpanda/";
            action = "WEIGH";
            weight.adjust = 20;
          }
          { import = "(data)/meta/default-config.yaml"; }
        ];
        dnsbl = false;
        status_codes = {
          CHALLENGE = 200;
          DENY = 200;
        };
        store = {
          backend = "memory";
          parameters = { };
        };
        thresholds = [
          {
            name = "minimal-suspicion";
            expression = "weight <= 0";
            action = "ALLOW";
          }
          {
            name = "mild-suspicion";
            expression.all = [
              "weight > 0"
              "weight < 10"
            ];
            action = "CHALLENGE";
            challenge = {
              algorithm = "metarefresh";
              difficulty = 1;
            };
          }
          {
            name = "moderate-suspicion";
            expression.all = [
              "weight >= 10"
              "weight < 20"
            ];
            action = "CHALLENGE";
            challenge = {
              algorithm = "fast";
              difficulty = 2;
            };
          }
          {
            name = "mild-proof-of-work";
            expression.all = [
              "weight >= 20"
              "weight < 30"
            ];
            action = "CHALLENGE";
            challenge = {
              algorithm = "fast";
              difficulty = 4;
            };
          }
          {
            name = "extreme-suspicion";
            expression = "weight >= 30";
            action = "CHALLENGE";
            challenge = {
              algorithm = "fast";
              difficulty = 6;
            };
          }
        ];
      };
    };

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
    '' + (lib.strings.optionalString config.custom.services.gitea.actions.enable ''

      # Redirect container SSH traffic directly to the Gitea SSH port
      iptables -t nat -A PREROUTING -s 10.108.27.2 -d 138.201.252.214 -p tcp --dport 22 -j REDIRECT --to-port ${toString cfg.sshPort}
      iptables -A INPUT -s 10.108.27.2 -d 10.108.27.1 -p tcp --dport ${toString cfg.sshPort} -j ACCEPT
    '');
  };
}
