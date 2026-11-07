{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.mail;

  hostname = "mx.jakehillion.me";
  ipv4 = "51.194.133.162";
  ipv6 = "2a11:2646:14b6:2::1";
  gateway4 = "10.214.61.1";
  gateway6 = "fe80::1";

  stateDirs = {
    "/var/lib/mail" = "mail";
    "/var/lib/rspamd" = "rspamd";
    "/var/lib/redis-rspamd" = "redis-rspamd";
    "/var/lib/acme" = "acme";
    "/var/spool/smtpd" = "smtpd";
    "/var/lib/fail2ban" = "fail2ban";
  };
in
{
  options.custom.services.mail = {
    enable = lib.mkEnableOption "mail";

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mail";
    };

    backup = lib.mkOption {
      default = true;
      type = lib.types.bool;
      description = "Enable backups to restic";
    };
  };

  config = lib.mkIf cfg.enable {
    custom.services.mail.dataPath = lib.mkIf config.custom.impermanence.enable (lib.mkOverride 999 "${config.custom.impermanence.base}/services/mail");

    age.secrets = {
      # Dovecot passwd-file, also read by OpenSMTPD's table-passwd
      "mail/passwd" = {
        rekeyFile = ./passwd.age;
        owner = toString config.ids.uids.dovecot2;
        group = toString config.ids.gids.smtpd;
        mode = "0440";
      };
      # Sieve filing for marketing mail. It names the senders, so it's kept
      # out of the repo.
      "mail/marketing.sieve" = {
        rekeyFile = ./marketing.sieve.agent.age;
        owner = toString config.ids.uids.vmail;
        mode = "0400";
      };
      # OpenSMTPD credentials table for the relay
      "mail/relay" = {
        rekeyFile = ./relay.age;
        group = toString config.ids.gids.smtpd;
        mode = "0440";
      };
      "backups/mail/restic/mig29" = lib.mkIf cfg.backup {
        rekeyFile = ../../../secrets/restic/mig29.age;
      };
    };

    systemd.tmpfiles.rules = [ "d ${cfg.dataPath} 0700 root root - -" ]
      ++ lib.attrsets.mapAttrsToList (_: dir: "d ${cfg.dataPath}/${dir} - - - - -") stateDirs;

    services.restic.backups."mail" = lib.mkIf cfg.backup {
      user = "root";
      timerConfig = {
        OnBootSec = "15m";
        OnUnitInactiveSec = "30m";
        RandomizedDelaySec = "5m";
      };
      repository = "rest:https://restic.${config.ogygia.domain}/mig29";
      passwordFile = config.age.secrets."backups/mail/restic/mig29".path;
      paths = [ "${cfg.dataPath}/mail" ];
    };

    systemd.services."container@mail" = {
      # nspawn fails if the macvlan's parent doesn't exist yet
      wants = [ "sys-subsystem-net-devices-dmz.device" ];
      after = [ "sys-subsystem-net-devices-dmz.device" ];
      # Secrets are bind-mounted as files, so the container only sees new ones on restart
      restartTriggers = [
        (builtins.hashFile "sha256" config.age.secrets."mail/passwd".rekeyFile)
        (builtins.hashFile "sha256" config.age.secrets."mail/relay".rekeyFile)
        (builtins.hashFile "sha256" config.age.secrets."mail/marketing.sieve".rekeyFile)
      ];
    };

    containers."mail" = {
      autoStart = true;
      ephemeral = true;
      privateUsers = "pick";

      macvlans = [ "dmz" ];
      # idmap keeps host ownership meaningful inside the user namespace
      bindMounts = lib.attrsets.mapAttrs (mountPoint: m: m // { mountPoint = "${mountPoint}:idmap"; }) (
        lib.attrsets.mapAttrs
          (_: dir: { hostPath = "${cfg.dataPath}/${dir}"; isReadOnly = false; })
          stateDirs // {
          "/run/agenix/mail/passwd".hostPath = config.age.secrets."mail/passwd".path;
          "/run/agenix/mail/relay".hostPath = config.age.secrets."mail/relay".path;
          "/run/agenix/mail/marketing.sieve".hostPath = config.age.secrets."mail/marketing.sieve".path;
        }
      );

      config = (hostConfig: { config, pkgs, ... }: {
        config = {
          system.stateVersion = "26.05";

          networking = {
            hostName = "mx";
            domain = "jakehillion.me";
            useHostResolvConf = false;
            firewall.allowedTCPPorts = [ 25 80 465 587 993 ];
          };

          systemd.network = {
            enable = true;
            networks."10-dmz" = {
              matchConfig.Name = "mv-dmz";
              linkConfig.MACAddress = "02:9c:3e:51:d7:a4";
              address = [ "${ipv4}/32" "${ipv6}/128" ];
              routes = [
                { Gateway = gateway4; GatewayOnLink = true; }
                { Gateway = gateway6; }
              ];
              networkConfig.IPv6AcceptRA = false;
            };
          };
          services.resolved.enable = false;

          # Recursive resolver: DNSBLs refuse queries from public resolvers
          services.unbound.enable = true;

          users = {
            users = {
              vmail = {
                uid = hostConfig.ids.uids.vmail;
                home = "/var/lib/mail";
              };
              acme.uid = hostConfig.ids.uids.acme;
              redis-rspamd.uid = hostConfig.ids.uids.redis-rspamd;
            };
            groups = {
              vmail.gid = hostConfig.ids.gids.vmail;
              acme.gid = hostConfig.ids.gids.acme;
              redis-rspamd.gid = hostConfig.ids.gids.redis-rspamd;
            };
          };

          systemd.tmpfiles.rules = [
            "d /var/lib/mail 0700 vmail vmail - -"
            # sieve_script_bin_path
            "d /var/cache/sieve 0700 vmail vmail - -"
          ];

          security.acme = {
            acceptTerms = true;
            defaults.email = "acme@hillion.co.uk";
            certs.${hostname} = {
              listenHTTP = ":80";
              reloadServices = [ "dovecot" "opensmtpd" ];
            };
          };

          services.opensmtpd = {
            enable = true;
            procPackages = [ pkgs.opensmtpd-table-passwd ];
            serverConfiguration =
              let
                virtuals = pkgs.writeText "virtuals" ''
                  jake@jakehillion.me vmail
                  @jakehillion.me jake@jakehillion.me
                '';
              in
              ''
                pki ${hostname} cert "/run/opensmtpd-pki/fullchain.pem"
                pki ${hostname} key "/run/opensmtpd-pki/key.pem"

                table users passwd:/run/agenix/mail/passwd
                table credentials file:/run/agenix/mail/relay
                table virtuals file:${virtuals}

                filter rspamd proc-exec "${pkgs.opensmtpd-filter-rspamd}/bin/filter-rspamd"

                listen on mv-dmz tls pki ${hostname} hostname ${hostname} filter rspamd
                listen on mv-dmz port 465 smtps pki ${hostname} hostname ${hostname} auth <users> mask-src
                listen on mv-dmz port 587 tls-require pki ${hostname} hostname ${hostname} auth <users> mask-src

                action "deliver" lmtp "/run/dovecot2/lmtp" rcpt-to virtual <virtuals>
                action "outbound" relay host smtp+tls://mythic@smtp-auth.mythic-beasts.com:587 auth <credentials> helo ${hostname}

                match from any for domain "jakehillion.me" action "deliver"
                match from auth for any action "outbound"
                match from local for any action "outbound"
              '';
          };

          systemd.services.opensmtpd = {
            wants = [ "network-online.target" "acme-${hostname}.service" ];
            after = [ "network-online.target" "acme-${hostname}.service" ];
            # OpenSMTPD only loads certificates and keys owned by root
            serviceConfig = {
              RuntimeDirectory = "opensmtpd-pki";
              ExecStartPre = "${pkgs.coreutils}/bin/install -o root -g root -m 0400 /var/lib/acme/${hostname}/fullchain.pem /var/lib/acme/${hostname}/key.pem /run/opensmtpd-pki";
            };
          };
          systemd.services.dovecot = {
            wants = [ "acme-${hostname}.service" ];
            after = [ "acme-${hostname}.service" ];
          };

          environment.systemPackages = [ config.services.dovecot2.package.passthru.dovecot_pigeonhole ];

          services.dovecot2 = {
            enable = true;

            sieve.pipeBins = map lib.meta.getExe [
              (pkgs.writeShellScriptBin "learn-spam" "exec ${config.services.rspamd.package}/bin/rspamc -h localhost:11334 learn_spam")
              (pkgs.writeShellScriptBin "learn-ham" "exec ${config.services.rspamd.package}/bin/rspamc -h localhost:11334 learn_ham")
            ];

            settings = {
              dovecot_config_version = "2.4.5";
              dovecot_storage_version = "2.4.5";

              protocols = {
                imap = true;
                lmtp = true;
              };

              mail_driver = "maildir";
              mail_home = "/var/lib/mail/%{user | domain}/%{user | username}";
              mail_path = "~/Maildir";
              # Maildir++ uses '.' as its separator, so it needs escaping
              # in folder names
              mailbox_list_storage_escape_char = "^";
              mail_uid = "vmail";
              mail_gid = "vmail";
              first_valid_uid = hostConfig.ids.uids.vmail;
              first_valid_gid = hostConfig.ids.gids.vmail;

              ssl = "required";
              ssl_server_cert_file = "/var/lib/acme/${hostname}/fullchain.pem";
              ssl_server_key_file = "/var/lib/acme/${hostname}/key.pem";

              "passdb passwd-file" = {
                passwd_file_path = "/run/agenix/mail/passwd";
                default_password_scheme = "CRYPT";
              };
              "userdb passwd-file".passwd_file_path = "/run/agenix/mail/passwd";

              "service imap-login" = {
                "inet_listener imap".port = 0;
                "inet_listener imaps" = {
                  port = 993;
                  ssl = true;
                };
              };
              "service lmtp"."unix_listener lmtp" = {
                user = "vmail";
                group = "vmail";
                mode = "0600";
              };

              "namespace inbox" = {
                inbox = true;
                separator = "/";
                "mailbox Archive" = {
                  special_use = "\\Archive";
                  auto = "subscribe";
                };
                "mailbox Drafts" = {
                  special_use = "\\Drafts";
                  auto = "subscribe";
                };
                "mailbox Junk" = {
                  special_use = "\\Junk";
                  auto = "subscribe";
                  mailbox_autoexpunge = "30d";
                };
                "mailbox Sent" = {
                  special_use = "\\Sent";
                  auto = "subscribe";
                };
                "mailbox Trash" = {
                  special_use = "\\Trash";
                  auto = "subscribe";
                  mailbox_autoexpunge = "30d";
                };
                "mailbox Marketing".auto = "subscribe";
                "mailbox \"Archived Accounts/jakehillion@live.co.uk\"".auto = "subscribe";
                "mailbox \"Archived Accounts/jshillion@hotmail.co.uk\"".auto = "subscribe";
              };

              "protocol lmtp" = {
                # OpenSMTPD's Delivered-To carries the original recipient
                lmtp_hdr_delivery_address = "none";
                mail_plugins.sieve = true;
                # Before scripts run in precedence order, and the sequence
                # ends at the first script that files the message
                "sieve_script filing" = {
                  type = "before";
                  precedence = 1;
                  path = ./filing.sieve;
                };
                "sieve_script marketing" = {
                  type = "before";
                  precedence = 2;
                  path = "/run/agenix/mail/marketing.sieve";
                };
              };

              # Train rspamd when mail moves into or out of Junk
              "protocol imap".mail_plugins.imap_sieve = true;
              sieve_plugins.sieve_imapsieve = true;
              sieve_global_extensions."vnd.dovecot.environment" = true;
              # Every script is read-only, so compiled binaries are cached here
              sieve_script_bin_path = "/var/cache/sieve";
              "mailbox Junk"."sieve_script learn-spam" = {
                type = "before";
                cause = "copy";
                path = ./learn-spam.sieve;
              };
              "imapsieve_from Junk"."sieve_script learn-ham" = {
                type = "before";
                cause = "copy";
                path = ./learn-ham.sieve;
              };
            };
          };

          services.rspamd = {
            enable = true;
            workers = {
              # Where filter-rspamd connects by default
              normal.bindSockets = [ "localhost:11333" ];
              controller = { };
            };
            locals."redis.conf".text = ''
              servers = "127.0.0.1:6379";
            '';
            # Apply the sender's DMARC policy: quarantine goes to Junk
            locals."dmarc.conf".text = ''
              actions {
                quarantine = "add_header";
                reject = "reject";
              }
            '';
            # Treat private ranges like any other sender. local.d merges
            # with the default list, so this has to replace it.
            overrides."options.inc".text = ''
              local_addrs = [];
            '';
          };
          services.redis.servers.rspamd = {
            enable = true;
            port = 6379;
            bind = "127.0.0.1";
          };

          # Port 25 is left to rspamd, as it takes no logins
          services.fail2ban = {
            enable = true;
            maxretry = 5;
            bantime = "1h";
            bantime-increment = {
              enable = true;
              maxtime = "14d";
            };
            jails = {
              dovecot-imap = {
                settings.port = "993";
                filter = {
                  INCLUDES.before = "common.conf";
                  Definition = {
                    _daemon = "dovecot";
                    failregex = ''^%(__prefix_line)simap-login: Login aborted: .* \(auth_failed\): .*\brip=<ADDR>,'';
                    journalmatch = "_SYSTEMD_UNIT=dovecot.service";
                  };
                };
              };
              # The address and the failure are logged on separate lines,
              # tied together by the session ID
              opensmtpd-auth = {
                settings.port = "465,587";
                filter = {
                  INCLUDES.before = "common.conf";
                  Definition = {
                    _daemon = "smtpd";
                    prefregex = ''^%(__prefix_line)s<F-MLFID>[0-9a-f]+</F-MLFID> <F-CONTENT>smtp (?:connected|authentication) .+</F-CONTENT>$'';
                    failregex = lib.strings.concatStringsSep "\n            " [
                      ''^<F-NOFAIL>smtp connected</F-NOFAIL> address=<ADDR> host=\S+$''
                      ''^smtp authentication user=\S* result=permfail$''
                    ];
                    journalmatch = "_SYSTEMD_UNIT=opensmtpd.service";
                  };
                };
              };
            };
          };
        };
      }) config;
    };
  };
}
