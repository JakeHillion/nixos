let
  users = {
    jake = {
      gendry = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw4lgH20nfuchDqvVf0YciqN0GnBw5hfh8KIun5z0P7wlNgVYnCyvPvdIlGf2Nt1z5EGfsMzMLhKDOZkcTMlhupd+j2Er/ZB764uVBGe1n3CoPeasmbIlnamZ12EusYDvQGm2hVJTGQPPp9nKaRxr6ljvTMTNl0KWlWvKP4kec74d28MGgULOPLT3HlAyvUymSULK4lSxFK0l97IVXLa8YwuL5TNFGHUmjoSsi/Q7/CKaqvNh+ib1BYHzHYsuEzaaApnCnfjDBNexHm/AfbI7s+g3XZDcZOORZn6r44dOBNFfwvppsWj3CszwJQYIFeJFuMRtzlC8+kyYxci0+FXHn";
      mbp = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw==";
    };
  };
  jake_users = builtins.attrValues users.jake;

  systems = {
    uk = {
      co = {
        hillion = {
          ts = {
            cx = {
              boron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtQy+FGs/2cN82X15LUGJk8iAAxkttEffwpNnpmLXdg root@boron";
              jorah = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA9Hp37ljgVRZwjXnTh+XqRuQWk23alOqe7ptwSr2A5 root@jorah";
            };
            home = {
              microserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPOCPqXm5a+vGB6PsJFvjKNgjLhM5MxrwCy6iHGRjXw root@microserver";
              router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
            };
            lt = { be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be"; };
            pop = { li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li"; };
            terminals = { jakehillion = { gendry = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPXM5aDvNv4MTITXAvJWSS2yvr/mbxJE31tgwJtcl38c root@gendry"; }; };
            storage = {
              tywin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGATsjWO0qZNFp2BhfgDuWi+e/ScMkFxp79N2OZoed1k root@tywin";
              theon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN59psLVu3/sQORA4x3p8H3ei8MCQlcwX5T+k3kBeBMf root@theon";
            };
          };
        };
      };
    };
  };
  all_systems = builtins.attrValues systems;

  ts = systems.uk.co.hillion.ts;
in
{
  # User Passwords
  "passwords/jake.age".publicKeys = jake_users ++ [
    ts.terminals.jakehillion.gendry
    ts.home.router
    ts.lt.be
  ];

  # Tailscale Pre-Auth Keys
  "tailscale/be.lt.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.lt.be ];
  "tailscale/boron.cx.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "tailscale/jorah.cx.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "tailscale/microserver.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.microserver ];
  "tailscale/li.pop.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.pop.li ];
  "tailscale/router.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.router ];
  "tailscale/theon.storage.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.storage.theon ];
  "tailscale/tywin.storage.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Resilio Sync Secrets
  ## Encrypted Resilio Sync Secrets
  "resilio/encrypted/dad.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/projects.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/resources.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/sync.age".publicKeys = jake_users ++ [ ];

  ## Read/Write Resilio Sync Secrets
  "resilio/plain/dad.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ts.storage.tywin ];
  "resilio/plain/joseph.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ts.storage.tywin ];
  "resilio/plain/projects.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ts.storage.tywin ];
  "resilio/plain/resources.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ts.storage.tywin ];
  "resilio/plain/sync.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ts.storage.tywin ];

  # Matrix Secrets
  "matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "matrix/matrix.hillion.co.uk/registration_shared_secret.age".publicKeys = jake_users ++ [ ts.cx.jorah ];

  # Backups Secrets
  "restic/128G.age".publicKeys = jake_users ++ [ ts.storage.tywin ts.cx.jorah ts.home.microserver ];
  "restic/1.6T.age".publicKeys = jake_users ++ [ ts.storage.tywin ts.home.router ];

  "git/git_backups_ecdsa.age".publicKeys = jake_users ++ [ ts.storage.tywin ];
  "git/git_backups_remotes.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Spotify Secrets
  "spotify/11132032266.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];

  # Mastodon Secrets
  "mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ];

  # Chia Secrets
  "chia/farmer.key.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Storj Secrets
  "storj/auth.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Version tracker secrets
  "version_tracker/ssh.key.age".publicKeys = jake_users ++ [ ts.cx.jorah ];

  # Home Automation secrets
  "mqtt/zigbee2mqtt.age".publicKeys = jake_users ++ [ ts.home.router ];
  "mqtt/homeassistant.age".publicKeys = jake_users ++ [ ];

  # Wireguard Secrets
  "wireguard/downloads.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Deluge Secrets
  "deluge/auth.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # Gitea Secrets
  "gitea/lfs_jwt_secret.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "gitea/mailer_password.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "gitea/oauth_jwt_secret.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "gitea/security_secret_key.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "gitea/security_internal_token.age".publicKeys = jake_users ++ [ ts.cx.jorah ];

  "gitea/actions/jorah.age".publicKeys = jake_users ++ [ ts.cx.jorah ];

  # HomeAssistant Secrets
  "homeassistant/secrets.yaml.age".publicKeys = jake_users ++ [ ts.home.microserver ];

  # Web certificates
  "certs/hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "certs/blog.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "certs/gitea.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "certs/homeassistant.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
  "certs/links.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.jorah ];
}
