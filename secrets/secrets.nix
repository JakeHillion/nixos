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
              boron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtcJ7HY/vjtheMV8EN2wlTw1hU53CJebGIeRJcSkzt5 root@boron";
            };
            home = {
              microserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPOCPqXm5a+vGB6PsJFvjKNgjLhM5MxrwCy6iHGRjXw root@microserver";
              router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
            };
            lt = { be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be"; };
            pop = {
              li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li";
              sodium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDQmG7v/XrinPmkTU2eIoISuU3+hoV4h60Bmbwd+xDjr root@sodium";
            };
            terminals = { jakehillion = { gendry = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPXM5aDvNv4MTITXAvJWSS2yvr/mbxJE31tgwJtcl38c root@gendry"; }; };
            st = { phoenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPQcp9MzabvwbViNmILVNfipMUnwV+5okRfhOuV7+Mt root@phoenix"; };
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
  "tailscale/li.pop.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.pop.li ];
  "tailscale/microserver.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.microserver ];
  "tailscale/phoenix.st.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.st.phoenix ];
  "tailscale/router.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.router ];
  "tailscale/sodium.pop.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.pop.sodium ];
  "tailscale/theon.storage.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.storage.theon ];
  "tailscale/tywin.storage.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.storage.tywin ];

  # WiFi Environment Files
  "wifi/be.lt.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.lt.be ];

  # Resilio Sync Secrets
  ## Encrypted Resilio Sync Secrets
  "resilio/encrypted/dad.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/projects.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/resources.age".publicKeys = jake_users ++ [ ];
  "resilio/encrypted/sync.age".publicKeys = jake_users ++ [ ];

  ## Read/Write Resilio Sync Secrets
  "resilio/plain/dad.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.terminals.jakehillion.gendry ts.cx.boron ];
  "resilio/plain/joseph.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.terminals.jakehillion.gendry ts.cx.boron ];
  "resilio/plain/projects.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.terminals.jakehillion.gendry ts.cx.boron ];
  "resilio/plain/resources.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.terminals.jakehillion.gendry ts.cx.boron ];
  "resilio/plain/sync.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.terminals.jakehillion.gendry ts.cx.boron ];

  # Matrix Secrets
  "matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "matrix/matrix.hillion.co.uk/registration_shared_secret.age".publicKeys = jake_users ++ [ ts.cx.boron ];

  "matrix/matrix.hillion.co.uk/syncv3_secret.age".publicKeys = jake_users ++ [ ts.cx.boron ];

  # Backups Secrets
  "restic/128G.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.cx.boron ts.home.microserver ];
  "restic/1.6T.age".publicKeys = jake_users ++ [ ts.st.phoenix ts.home.router ];

  "git/git_backups_ecdsa.age".publicKeys = jake_users ++ [ ts.st.phoenix ];
  "git/git_backups_remotes.age".publicKeys = jake_users ++ [ ts.st.phoenix ];

  # Mastodon Secrets
  "mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ];
  "mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ];

  # Chia Secrets
  "chia/farmer.key.age".publicKeys = jake_users ++ [ ts.st.phoenix ];

  # Storj Secrets
  "storj/auth.age".publicKeys = jake_users ++ [ ];

  # Version tracker secrets
  "version_tracker/ssh.key.age".publicKeys = jake_users ++ [ ts.cx.boron ];

  # Home Automation secrets
  "mqtt/zigbee2mqtt.age".publicKeys = jake_users ++ [ ts.home.router ];
  "mqtt/homeassistant.age".publicKeys = jake_users ++ [ ];

  # Wireguard Secrets
  "wireguard/downloads.age".publicKeys = jake_users ++ [ ts.st.phoenix ];

  # Deluge Secrets
  "deluge/auth.age".publicKeys = jake_users ++ [ ts.st.phoenix ];

  # Gitea Secrets
  "gitea/lfs_jwt_secret.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "gitea/mailer_password.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "gitea/oauth_jwt_secret.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "gitea/security_secret_key.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "gitea/security_internal_token.age".publicKeys = jake_users ++ [ ts.cx.boron ];

  "gitea/actions/boron.age".publicKeys = jake_users ++ [ ts.cx.boron ];

  # HomeAssistant Secrets
  "homeassistant/secrets.yaml.age".publicKeys = jake_users ++ [ ts.home.microserver ];

  # Web certificates
  "certs/hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "certs/blog.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "certs/gitea.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "certs/homeassistant.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.boron ];
  "certs/links.hillion.co.uk.pem.age".publicKeys = jake_users ++ [ ts.cx.boron ];
}
