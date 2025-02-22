let
  users = {
    jake = {
      gendry = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw4lgH20nfuchDqvVf0YciqN0GnBw5hfh8KIun5z0P7wlNgVYnCyvPvdIlGf2Nt1z5EGfsMzMLhKDOZkcTMlhupd+j2Er/ZB764uVBGe1n3CoPeasmbIlnamZ12EusYDvQGm2hVJTGQPPp9nKaRxr6ljvTMTNl0KWlWvKP4kec74d28MGgULOPLT3HlAyvUymSULK4lSxFK0l97IVXLa8YwuL5TNFGHUmjoSsi/Q7/CKaqvNh+ib1BYHzHYsuEzaaApnCnfjDBNexHm/AfbI7s+g3XZDcZOORZn6r44dOBNFfwvppsWj3CszwJQYIFeJFuMRtzlC8+kyYxci0+FXHn";
      mbp = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw==";
      boron = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7lfShRwA4hycaT4eP1PCQ45jr9JXwrZeOmn/TTLJu0k6x6AClHShYj2HnbBMd9SxIz+pRHtBz7fxBQeDEhorccI6F8jxLPz4mrBiGGJMFvdeOh4sCJ0gIIKFd9vmY1pI7AD0mden7xqCkGIS876aIRCTY32aCbyqID7FNkV7DvTNnxDf+jCszoSIt73PwRCtNyg7aPNsqq6FL3NpzW4Y/jJ9+V+lmPZGUqf6OtgJMzU6KHPN/1VW09K0Buto12h+mIc/IhdRsJ0pnp1wdcFut3kNdr0TeiXQ++KjVKZb8JLw5aPbDTm9To5fJexrGVNoWIAL1I70L5hrjx9gFLBWRmnzDcFO983e9ikkePMqg4t1+gq+mdGJnLyE8paqXn/C0jDxZM9P6dYrAn2dCNb602R2gN6bzyLmICQZDtGRVpN2BsW2kYyJ7T102C3X0c8Bb1yoILDEw3K5z8Xph4QR8K39jUTUGnZHRG9xI2/HsqJg3voGfAj/uDXebxhvVClfviB4BJRr7Ip0Z2OqHaP1kt1JyutnQ+ICm63Xm8c/Wo4Jg2esr74Zkvwdgj9L6/BmivuaP5dZ3OctRtXfqPCadgIfrAET04l9tUoAv1b0kiiZ29+mi4El1RrN2vL4zAoguQlLWPbFmH6sTjVulFY70PalmoC6oiEJUWggE0Lb5iw== jake@boron";
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
          home = {
            router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
          };
          lt = { be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be"; };
          pop = {
            li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li";
            sodium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDQmG7v/XrinPmkTU2eIoISuU3+hoV4h60Bmbwd+xDjr root@sodium";
            stinger = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID28NGGSaK1OtpQkQnYqSZWSahX25uboiHwhsYQoKKbL root@stinger";
          };
          rig = { merlin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN99UrXe3puoW0Jr1bSPRHL6ImLZD9A9sXeE54JFggIC root@merlin"; };
          st = { phoenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPQcp9MzabvwbViNmILVNfipMUnwV+5okRfhOuV7+Mt root@phoenix"; };
          storage = {
            theon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN59psLVu3/sQORA4x3p8H3ei8MCQlcwX5T+k3kBeBMf root@theon";
          };
          terminals = { jakehillion = { gendry = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPXM5aDvNv4MTITXAvJWSS2yvr/mbxJE31tgwJtcl38c root@gendry"; }; };
        };
      };
    };
  };
  all_systems = builtins.attrValues systems;

  neb = systems.me.jakehillion.neb;
in
{
  # User Passwords
  "passwords/jake.age".publicKeys = jake_users ++ [
    neb.home.router
    neb.lt.be
    neb.rig.merlin
    neb.st.phoenix
    neb.terminals.jakehillion.gendry
  ];

  # WiFi Environment Files
  "wifi/be.lt.neb.jakehillion.me.age".publicKeys = jake_users ++ [ neb.lt.be ];

  # Matrix Secrets
  "matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "matrix/matrix.hillion.co.uk/registration_shared_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  "matrix/matrix.hillion.co.uk/syncv3_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Backups Secrets
  "restic/128G.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.cx.boron neb.pop.stinger ];
  "restic/128G-wasabi.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "restic/128G-backblaze.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "restic/1.6T.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.home.router neb.pop.stinger ];
  "restic/1.6T-wasabi.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "restic/1.6T-backblaze.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "git/git_backups_ecdsa.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "git/git_backups_remotes.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Mastodon Secrets
  "mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ];

  # Chia Secrets
  "chia/farmer.key.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Storj Secrets
  "storj/auth.age".publicKeys = jake_users ++ [ ];

  # Version tracker secrets
  "version_tracker/ssh.key.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Home Automation secrets
  "mqtt/zigbee2mqtt.age".publicKeys = jake_users ++ [ neb.home.router ];
  "mqtt/homeassistant.age".publicKeys = jake_users ++ [ ];

  # Wireguard Secrets
  "wireguard/downloads.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Deluge Secrets
  "deluge/auth.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Gitea Secrets
  "gitea/lfs_jwt_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "gitea/mailer_password.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "gitea/oauth_jwt_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "gitea/security_secret_key.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "gitea/security_internal_token.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  "gitea/actions/boron.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # HomeAssistant Secrets
  "homeassistant/secrets.yaml.age".publicKeys = jake_users ++ [ neb.pop.stinger ];

  # Web certificates
  "certs/hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "certs/blog.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "certs/gitea.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "certs/homeassistant.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "certs/links.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Cloudflare
  "cloudflare/zone_keys.env.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Frigate secrets
  "frigate/secrets.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Desktop secrets
  "sway/timewall/merlin.rig.neb.jakehillion.me.toml.age".publicKeys = jake_users ++ [ neb.rig.merlin ];
  "sway/timewall/be.lt.neb.jakehillion.me.toml.age".publicKeys = jake_users ++ [ neb.lt.be ];
}
