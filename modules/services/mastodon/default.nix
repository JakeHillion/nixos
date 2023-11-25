{ config, pkgs, lib, ... }:

let
  cfg = config.custom.services.mastodon;
in
{
  options.custom.services.mastodon = {
    enable = lib.mkEnableOption "mastodon";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      "mastodon/otp_secret_file" = {
        file = ../../../secrets/mastodon/social.hillion.co.uk/otp_secret_file.age;
        owner = config.services.mastodon.user;
        group = config.services.mastodon.group;
      };
      "mastodon/secret_key_base" = {
        file = ../../../secrets/mastodon/social.hillion.co.uk/secret_key_base.age;
        owner = config.services.mastodon.user;
        group = config.services.mastodon.group;
      };
      "mastodon/vapid_private_key" = {
        file = ../../../secrets/mastodon/social.hillion.co.uk/vapid_private_key.age;
        owner = config.services.mastodon.user;
        group = config.services.mastodon.group;
      };
      "mastodon/mastodon_at_social.hillion.co.uk" = {
        file = ../../../secrets/mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age;
        owner = config.services.mastodon.user;
        group = config.services.mastodon.group;
      };
    };

    services = {
      mastodon = {
        enable = true;
        localDomain = "social.hillion.co.uk";

        vapidPublicKeyFile = builtins.path { path = ./vapid_public_key; };
        otpSecretFile = config.age.secrets."mastodon/otp_secret_file".path;
        secretKeyBaseFile = config.age.secrets."mastodon/secret_key_base".path;
        vapidPrivateKeyFile = config.age.secrets."mastodon/vapid_private_key".path;

        smtp = {
          user = "mastodon@social.hillion.co.uk";
          port = 587;
          passwordFile = config.age.secrets."mastodon/mastodon_at_social.hillion.co.uk".path;
          host = "smtp.eu.mailgun.org";
          fromAddress = "mastodon@social.hillion.co.uk";
          authenticate = true;
        };

        extraConfig = {
          EMAIL_DOMAIN_WHITELIST = "hillion.co.uk";
        };
      };

      caddy = {
        enable = true;

        virtualHosts."social.hillion.co.uk".extraConfig = ''
          handle_path /system/* {
            file_server * {
              root /var/lib/mastodon/public-system
            }
          }

          handle /api/v1/streaming/* {
            reverse_proxy  unix//run/mastodon-streaming/streaming.socket
          }
        
          route * {
            file_server * {
              root ${pkgs.mastodon}/public
              pass_thru
            }
            reverse_proxy * unix//run/mastodon-web/web.socket
          }

          handle_errors {
            root * ${pkgs.mastodon}/public
            rewrite 500.html
            file_server
          }

          encode gzip

          header /* {
            Strict-Transport-Security "max-age=31536000;"
          }
          header /emoji/* Cache-Control "public, max-age=31536000, immutable"
          header /packs/* Cache-Control "public, max-age=31536000, immutable"
          header /system/accounts/avatars/* Cache-Control "public, max-age=31536000, immutable"
          header /system/media_attachments/files/* Cache-Control "public, max-age=31536000, immutable"
        '';
      };
    };
  };
}
