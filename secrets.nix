let
  users = {
    jake = {
      boron = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7lfShRwA4hycaT4eP1PCQ45jr9JXwrZeOmn/TTLJu0k6x6AClHShYj2HnbBMd9SxIz+pRHtBz7fxBQeDEhorccI6F8jxLPz4mrBiGGJMFvdeOh4sCJ0gIIKFd9vmY1pI7AD0mden7xqCkGIS876aIRCTY32aCbyqID7FNkV7DvTNnxDf+jCszoSIt73PwRCtNyg7aPNsqq6FL3NpzW4Y/jJ9+V+lmPZGUqf6OtgJMzU6KHPN/1VW09K0Buto12h+mIc/IhdRsJ0pnp1wdcFut3kNdr0TeiXQ++KjVKZb8JLw5aPbDTm9To5fJexrGVNoWIAL1I70L5hrjx9gFLBWRmnzDcFO983e9ikkePMqg4t1+gq+mdGJnLyE8paqXn/C0jDxZM9P6dYrAn2dCNb602R2gN6bzyLmICQZDtGRVpN2BsW2kYyJ7T102C3X0c8Bb1yoILDEw3K5z8Xph4QR8K39jUTUGnZHRG9xI2/HsqJg3voGfAj/uDXebxhvVClfviB4BJRr7Ip0Z2OqHaP1kt1JyutnQ+ICm63Xm8c/Wo4Jg2esr74Zkvwdgj9L6/BmivuaP5dZ3OctRtXfqPCadgIfrAET04l9tUoAv1b0kiiZ29+mi4El1RrN2vL4zAoguQlLWPbFmH6sTjVulFY70PalmoC6oiEJUWggE0Lb5iw== jake@boron";
      maverick = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3YCT92fn/2fKdT7Foax33ICkxOnGHWjWCElQIgTZnZEa11xSflVhAYMvzDhqDCBF9nbWqdj/op9urlYsmmwatwNZtDRWHzaX4Y8Qjw+WHOCQHGKi5vvMVQlYAAXzb4pCxkNktR5QUILsoTcT3fDIdtTXFAmrB4f7dLE2GeVWec9lY9Q/aH6qmV2dSxRwkg7Gc6Ur9xlnJUO4IwZS08YjZq/WcBAThlX/DFqh1d299uHKM/qAF4hf1k/ii2aruC51+vP4tI/K0GCf/sglUMvFIk2ALoKEq8LWZI5HjdcC1Brl9qhTkOts48UuniHcNfBL0rwtJj+QCvHe3KiN+9Sv/6twQ119e3xmQMYFJDI3lKat3B01geNMwfaCoRogCyeJ8yRZz0V/72DHm9HWwezfnzDmFmrTi9rsYmaaDhYYGW+vv1PeOT9mwEbUxhjllHsAJtImWQQbOGFDcY6d2YHI1theYWs/5zqc013ykE2FglGFlfmiap+O3MwkI9dyiX5bKgo4R+FBFa/NxxUmrV39k4IDPo/6LA+WxjzDSvaP+rpgAbwNBT8Qy49l97skvDtwnBzm9Ra295LTXeb/twApczHu6DbjZopQgzbTfEtG4HZx7T0HTZ0Az1uFas/h4AyK9avhODJXR/r/2KATKsOf6+h1GgIpchETQ4yh10+aS2Q== jake@maverick";
      mbp = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw==";
      rooster = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCqISEHUB1s/l1hV+YOj5EKgsNoUR8MukhcJpUqtfI+Xw+TYLStjPizGtAOG5+33VEt5eocw7RvnWLorJ2NPtGs7gaMZWasKvaRrXAiBiCreCCJp/vedHNxNtwa4nMKlW1o6oKStRiSFa53khdz5DmcRnsoxRPPON50JAbMgBAUmaxo6T8q1W3QOZ6kl6hjEBo+vuDHwxV8S7s+cao6OIvUduBeO/4wMYPuPVmI15ICP99vtQPGqGV9j1U8IHOJH2dzmR1SVEZFtfFmskr22wTEAOHU7XMIjFjgUUgWq4yLJSzx+dT6CKjiG/iR7RTSKFZCLxn/JJOlbo7wYWNbf2Ekhc1ujcZHBgmm+4gmZkTmyWqs6JGpdndrP0ae3prL9ZatnMnCobuYoB33j2tUOxdoxXt31j1fzvHuk4V1AUnaSxlWmTfsnpNaH+ngkA2fGlNAeLITXw3VjS/1HBNLC9KmWSF1Feu5nKPqL2CnFtYAsU8xS1wouIz0pDlFFR7xbd4Haw9+bW0G8VsJevnm+wMiziaI6WIknMTGl+De9L2FpY5T0lx0oIWH/uK7P0512ldHP0dTR3FmRfbODQQPvoR3Ryk9A57E+qu+5NP3jXA3SlmWJOnGiqvrwZW2WKCeGsv7PvK1gLw+P8EMrLkQ/cFsVFWfQYgEkBcSno4cywX8EQ== jake@rooster";
      bob = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCes0C/IoV3hgp4UmCAlJe+FEvZkY1vsiNx42lJQ33CZnxSP2qNfAokUJwpRA2WBACOz10EMIu0397B5TxWXu+zGWqqmsOjDfqZtgtKcJ9wNeNLi9qNrpi0WnmdiyiK+gsbCg6lOYcLCL2ARAnEs2LpCGaWd0VHglsF8X8npiI07udaIBEKnMqxYsRHzx7iRVCoA7/jFEFZrR3GXecDDzF0z6s3aAWvTfAaEJNIxz8rV81V9+lQp3CEOUPsF0J8fPxBLEcrBeYp14CQEMhqse5U/zOhvM2Uel71bfqeh1oaiiwPKGD21cw9DK7OQ7+Dk7LZ+AHxub9uqQie8jdHzyHhYhrZ9S3/YDuYJLk9Wel04BkkBw4jhvpRWwC561mNjOjTSKR+/xjKzSUgK84c/2Gf7kHR8GHpC6E/MEyR4YSHv1aFAuCzbfcqxgwKMwdLCcXfxAbGzVrvYyVP0TIrW+t/F7SIOWJxBG+ZLfJ0lhSDlBhr1LSXY9QJG/pYfuW+SF8ekUy3gOfVNoOd0/pYzb0+0UIJsTU16hMCwLlGeoKXO0LjJWahTiPWM/ATBXQhb0S+cChgvR0Did5F0i/dhh+5FziN/ULYqErO4yhQd06P5ibDKQrDFfR8k2gmp3LT/fo6rNGTLshxKwQnve9wd+OTbrSBWnMFbxwek042oS8J8w== jake@bob";
    };
  };
  jake_users = builtins.attrValues users.jake;

  systems = {
    me = {
      jakehillion = {
        neb = {
          cx = {
            boron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtcJ7HY/vjtheMV8EN2wlTw1hU53CJebGIeRJcSkzt5 root@boron";
            fanboy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIef6aIA1FBDoj8r2EQc8jPHxDLEUlNkkb6znMYtJhAp root@fanboy";
            maverick = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoaX0F3ytrDVfDuCr09dRazk1ZdQaD7/+e9SuMDl8gN root@maverick";
            rooster = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVOycZ4M9JYWtKnMeHwUgtJ1H+cECHE+67n1JDCLGle root@rooster";
            warlock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAPwB61OXWt+hpCV+T68MHTk06NptNBRgUTr/44Q6itT root@warlock";
          };
          gw = {
            cyclone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJM3XMKyjK4gYWkZ2byGewWiNI0RfVXK/wynv7bKzMmJ root@cyclone";
          };
          home = {
            router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
          };
          lt = {
            be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be";
            bob = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZHzsley+mbIio2UHmmraS0lHnYTwAKb3aOCfi/veoZ root@bob";
          };
          pop = {
            li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li";
            slider = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFABZxZAYPVqQ4+ZShrOvPopUrWHrnj47BnFJJwjdpwD root@slider";
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
    neb.lt.bob
    neb.rig.merlin
    neb.st.phoenix
  ];

  # WiFi Environment Files
  "secrets/wifi/be.lt.neb.jakehillion.me.age".publicKeys = jake_users ++ [ neb.lt.be ];
  "hosts/bob.lt.neb.jakehillion.me/wifi.env.age".publicKeys = [ users.jake.bob neb.lt.bob ];

  # Matrix Secrets
  "modules/services/matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ neb.cx.boron ];
  "modules/services/matrix/matrix.hillion.co.uk/registration_shared_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  "modules/services/matrix/matrix.hillion.co.uk/syncv3_secret.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Backups Secrets
  "secrets/restic/mig29.age".publicKeys = [
    neb.cx.boron
    neb.cx.rooster
    neb.cx.maverick
    neb.cx.warlock
    neb.pop.stinger
    neb.rig.merlin
    neb.st.phoenix
  ];
  "secrets/restic/b52.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.home.router neb.pop.stinger ];

  "modules/services/restic/aws-eu-central-2.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "modules/services/restic/aws-us-east-1.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "secrets/restic/1.6T-wasabi.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];
  "secrets/restic/1.6T-backblaze.env.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  "secrets/git/git_backups_ecdsa.age".publicKeys = jake_users ++ [ neb.st.phoenix neb.cx.warlock ];
  "secrets/git/git_backups_remotes.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Mastodon Secrets
  "modules/services/mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ];
  "modules/services/mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ];

  # Nix Builder
  "modules/services/nix-builder/gitea-token.age".publicKeys = [ neb.cx.boron neb.pop.slider ];

  # Chia Secrets
  "secrets/chia/farmer.key.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # Storj Secrets
  "secrets/storj/auth.age".publicKeys = jake_users ++ [ ];

  # Version tracker secrets
  "secrets/version_tracker/ssh.key.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Home Automation secrets
  "secrets/mqtt/zigbee2mqtt.age".publicKeys = jake_users ++ [ neb.pop.stinger ];
  "secrets/mqtt/homeassistant.age".publicKeys = jake_users ++ [ ];

  # Downloads Secrets
  "modules/services/downloads/wireguard.age".publicKeys = [ neb.st.phoenix ];
  "modules/services/downloads/deluge_auth.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

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

  # hearthd Secrets
  "modules/services/hearthd/locations.toml.age".publicKeys = [ neb.pop.stinger ];
  "modules/services/hearthd/mqtt.toml.age".publicKeys = [ neb.pop.stinger ];

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

  # Merlin boot control
  "hosts/merlin.rig.neb.jakehillion.me/homeassistant-api-token.age".publicKeys = jake_users ++ [ neb.rig.merlin ];

  # Radicale secrets
  "secrets/radicale/users.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Renovate secrets
  "modules/services/renovate/environment.age".publicKeys = jake_users ++ [ neb.cx.boron ];

  # Home configuration secrets
  "secrets/home/smtp-password.age".publicKeys = jake_users ++ [
    neb.cx.boron
    neb.cx.maverick
    neb.cx.rooster
    neb.lt.bob
    neb.rig.merlin
  ];

  # Offline YouTube secrets
  "modules/services/offline-youtube/playlist.env.age".publicKeys = [ neb.st.phoenix ];

  # Blackmagic camera importer
  "modules/services/blackmagic-cam-importer/immich-api-key.age".publicKeys = jake_users ++ [ neb.st.phoenix ];

  # mautrix-discord bridge
  "modules/services/mautrix-discord/registration.yaml.age".publicKeys = jake_users ++ [
    neb.cx.boron # Synapse needs registration
    neb.cx.warlock # Bridge needs registration
  ];
  "modules/services/mautrix-discord/environment.age".publicKeys = jake_users ++ [
    neb.cx.warlock # Bridge needs tokens
  ];

  # Firefly III
  "modules/services/firefly-iii/app-key.age".publicKeys = jake_users ++ [ neb.cx.warlock ];
  "modules/services/firefly-iii/access-token.age".publicKeys = [ neb.cx.warlock ];

  # async-coder secrets
  "modules/services/async-coder/maverick.cx.password.age".publicKeys = [ neb.cx.maverick ];

  # Cachix private cache credentials
  "modules/profiles/devbox-cachix-netrc.age".publicKeys = jake_users ++ [
    neb.cx.maverick
    neb.cx.rooster
    neb.lt.bob
    neb.rig.merlin
  ];

  # OpenClaw secrets
  "modules/services/openclaw/environment.age".publicKeys = jake_users ++ [ neb.cx.fanboy ];
}
