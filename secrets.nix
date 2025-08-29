let
  users = {
    jake = {
      mbp = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw==";
      boron = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7lfShRwA4hycaT4eP1PCQ45jr9JXwrZeOmn/TTLJu0k6x6AClHShYj2HnbBMd9SxIz+pRHtBz7fxBQeDEhorccI6F8jxLPz4mrBiGGJMFvdeOh4sCJ0gIIKFd9vmY1pI7AD0mden7xqCkGIS876aIRCTY32aCbyqID7FNkV7DvTNnxDf+jCszoSIt73PwRCtNyg7aPNsqq6FL3NpzW4Y/jJ9+V+lmPZGUqf6OtgJMzU6KHPN/1VW09K0Buto12h+mIc/IhdRsJ0pnp1wdcFut3kNdr0TeiXQ++KjVKZb8JLw5aPbDTm9To5fJexrGVNoWIAL1I70L5hrjx9gFLBWRmnzDcFO983e9ikkePMqg4t1+gq+mdGJnLyE8paqXn/C0jDxZM9P6dYrAn2dCNb602R2gN6bzyLmICQZDtGRVpN2BsW2kYyJ7T102C3X0c8Bb1yoILDEw3K5z8Xph4QR8K39jUTUGnZHRG9xI2/HsqJg3voGfAj/uDXebxhvVClfviB4BJRr7Ip0Z2OqHaP1kt1JyutnQ+ICm63Xm8c/Wo4Jg2esr74Zkvwdgj9L6/BmivuaP5dZ3OctRtXfqPCadgIfrAET04l9tUoAv1b0kiiZ29+mi4El1RrN2vL4zAoguQlLWPbFmH6sTjVulFY70PalmoC6oiEJUWggE0Lb5iw== jake@boron";
      rooster = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCqISEHUB1s/l1hV+YOj5EKgsNoUR8MukhcJpUqtfI+Xw+TYLStjPizGtAOG5+33VEt5eocw7RvnWLorJ2NPtGs7gaMZWasKvaRrXAiBiCreCCJp/vedHNxNtwa4nMKlW1o6oKStRiSFa53khdz5DmcRnsoxRPPON50JAbMgBAUmaxo6T8q1W3QOZ6kl6hjEBo+vuDHwxV8S7s+cao6OIvUduBeO/4wMYPuPVmI15ICP99vtQPGqGV9j1U8IHOJH2dzmR1SVEZFtfFmskr22wTEAOHU7XMIjFjgUUgWq4yLJSzx+dT6CKjiG/iR7RTSKFZCLxn/JJOlbo7wYWNbf2Ekhc1ujcZHBgmm+4gmZkTmyWqs6JGpdndrP0ae3prL9ZatnMnCobuYoB33j2tUOxdoxXt31j1fzvHuk4V1AUnaSxlWmTfsnpNaH+ngkA2fGlNAeLITXw3VjS/1HBNLC9KmWSF1Feu5nKPqL2CnFtYAsU8xS1wouIz0pDlFFR7xbd4Haw9+bW0G8VsJevnm+wMiziaI6WIknMTGl+De9L2FpY5T0lx0oIWH/uK7P0512ldHP0dTR3FmRfbODQQPvoR3Ryk9A57E+qu+5NP3jXA3SlmWJOnGiqvrwZW2WKCeGsv7PvK1gLw+P8EMrLkQ/cFsVFWfQYgEkBcSno4cywX8EQ== jake@rooster";
    };
  };
  jake_users = builtins.attrValues users.jake;

  systems = {
    me = {
      jakehillion = {
        neb = {
          cx = {
            boron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtcJ7HY/vjtheMV8EN2wlTw1hU53CJebGIeRJcSkzt5 root@boron";
          };
          gw = {
            cyclone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJM3XMKyjK4gYWkZ2byGewWiNI0RfVXK/wynv7bKzMmJ root@cyclone";
          };
          home = {
            router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
          };
          lt = { be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be"; };
          pop = {
            li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li";
            stinger = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID28NGGSaK1OtpQkQnYqSZWSahX25uboiHwhsYQoKKbL root@stinger";
          };
          rig = { merlin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN99UrXe3puoW0Jr1bSPRHL6ImLZD9A9sXeE54JFggIC root@merlin"; };
          st = { phoenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPQcp9MzabvwbViNmILVNfipMUnwV+5okRfhOuV7+Mt root@phoenix"; };
          storage = {
            theon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN59psLVu3/sQORA4x3p8H3ei8MCQlcwX5T+k3kBeBMf root@theon";
          };
        };
      };
    };
  };
  all_systems = builtins.attrValues systems;

  neb = systems.me.jakehillion.neb;
in
{
  # User Passwords
  "secrets/passwords/jake.age".publicKeys = jake_users ++ [
    neb.gw.cyclone
    neb.home.router
    neb.lt.be
    neb.rig.merlin
    neb.st.phoenix
  ];

  # WiFi Environment Files
  "secrets/wifi/be.lt.${config.ogygia.domain}.age".publicKeys = jake_users ++ [ neb.lt.be ];

  # Matrix Secrets
  "modules/services/matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/matrix/matrix.hillion.co.uk/registration_shared_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  "modules/services/matrix/matrix.hillion.co.uk/syncv3_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Backups Secrets
  "secrets/restic/mig29.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.cx.boron neb.pop.stinger ];
  "secrets/restic/b52.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.home.router neb.pop.stinger ];

  "modules/services/restic/aws-eu-central-2.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "modules/services/restic/aws-us-east-1.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "secrets/restic/1.6T-wasabi.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "secrets/restic/1.6T-backblaze.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "secrets/git/git_backups_ecdsa.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "secrets/git/git_backups_remotes.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Mastodon Secrets
  "modules/services/mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ];

  # Attic
  "secrets/attic/environment.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Chia Secrets
  "secrets/chia/farmer.key.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Storj Secrets
  "secrets/storj/auth.age".publicKeys = jake_users ++ [ ];

  # Version tracker secrets
  "secrets/version_tracker/ssh.key.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Home Automation secrets
  "secrets/mqtt/zigbee2mqtt.age".publicKeys = jake_users ++ [ neb.pop.stinger ];
  "secrets/mqtt/homeassistant.age".publicKeys = jake_users ++ [ ];

  # Wireguard Secrets
  "secrets/wireguard/downloads.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Deluge Secrets
  "secrets/deluge/auth.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Gitea Secrets
  "modules/services/gitea/lfs_jwt_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/gitea/mailer_password.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/gitea/oauth_jwt_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/gitea/security_secret_key.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/gitea/security_internal_token.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  "modules/services/gitea/actions/boron.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # HomeAssistant Secrets
  "secrets/homeassistant/secrets.yaml.age".publicKeys = jake_users ++ [ neb.pop.stinger ];
  "modules/services/homeassistant/pdu_password.age".publicKeys = [ neb.pop.stinger ];

  # Web certificates
  "secrets/certs/hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/blog.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/git.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/gitea.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/homeassistant.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/links.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/pastes.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "secrets/certs/status.jakehillion.me.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Cloudflare
  "secrets/cloudflare/zone_keys.env.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Frigate secrets
  "secrets/frigate/secrets.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Desktop secrets
  "secrets/sway/timewall/merlin.rig.${config.ogygia.domain}.toml.age".publicKeys = jake_users ++ [ neb.rig.merlin ];
  "secrets/sway/timewall/be.lt.${config.ogygia.domain}.toml.age".publicKeys = jake_users ++ [ neb.lt.be ];

  # Merlin boot control
  "hosts/merlin.rig.${config.ogygia.domain}/homeassistant-api-token.age".publicKeys = jake_users ++ [ neb.rig.merlin ];

  # Radicale secrets
  "secrets/radicale/users.age".publicKeys = jake_users ++ [ neb.cx.boron ];
}
