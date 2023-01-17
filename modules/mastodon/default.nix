{ config, pkgs, lib, ... }:

let
  cfg = config.services.mastodon;
  secrets = config.age.secrets;
in
{
  ## Mastodon (social.hillion.co.uk)
  ### OTP Secret
  secrets."mastodon/social.hillion.co.uk/otp_secret_file" = {
    file = ../../secrets/mastodon/social.hillion.co.uk/vapid_public_key.age;
    owner = cfg.user;
    group = cfg.group;
  };
  ### Secret Key Base Secret
  secrets."mastodon/social.hillion.co.uk/secret_key_base" = {
    file = ../../secrets/mastodon/social.hillion.co.uk/secret_key_base.age;
    owner = cfg.user;
    group = cfg.group;
  };
  ### Vapid Private Key Secret
  secrets."mastodon/social.hillion.co.uk/vapid_private_key" = {
    file = ../../secrets/mastodon/social.hillion.co.uk/vapid_private_key.age;
    owner = cfg.user;
    group = cfg.group;
  };
  ### SMTP Secret
  secrets."mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk" = {
    file = ../../secrets/mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age;
    owner = cfg.user;
    group = cfg.group;
  };

  cfg.enable = true;
  cfg.localDomain = "social.hillion.co.uk";

  cfg.vapidPublicKeyFile = builtins.readFile ./vapid_public_key;
  cfg.otpSecretFile = secrets."mastodon/social.hillion.co.uk/otp_secret_file".file;
  cfg.secretKeyBaseFile = secrets."mastodon/social.hillion.co.uk/secret_key_base".file;
  cfg.vapidPrivateKeyFile = secrets."mastodon/social.hillion.co.uk/vapid_private_key".file;

  cfg.smtp = {
    user = "mastodon@social.hillion.co.uk";
    port = 465;
    passwordFile = secrets."mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk".file;
    host = "smtp.eu.mailgun.org";
    fromAddress = "mastodon@social.hillion.co.uk";
    authenticate = true;
  };

  cfg.extraConfig = {
    EMAIL_DOMAIN_WHITELIST = "hillion.co.uk";
  };
}
