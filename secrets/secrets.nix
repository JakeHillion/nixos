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
            home = {
              microserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPOCPqXm5a+vGB6PsJFvjKNgjLhM5MxrwCy6iHGRjXw root@microserver";
              router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
            };
            parents = { microserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0cjjNQPnJwpu4wcYmvfjB1jlIfZwMxT+3nBusoYQFr root@microserver"; };
            strangervm = { vm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINb9mgyD/G3Rt6lvO4c0hoaVOlLE8e3+DUfAoB1RI5cy root@vm"; };
            terminals = { jakehillion = { gendry = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPXM5aDvNv4MTITXAvJWSS2yvr/mbxJE31tgwJtcl38c root@gendry"; }; };
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
  "passwords/gendry.jakehillion-terminals.ts.hillion.co.uk/jake.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];

  # Tailscale Pre-Auth Keys
  "tailscale/gendry.jakehillion-terminals.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "tailscale/microserver.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.microserver ];
  "tailscale/microserver.parents.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.parents.microserver ];
  "tailscale/router.home.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.home.router ];
  "tailscale/vm.strangervm.ts.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  # Resilio Sync Secrets
  ## Encrypted Resilio Sync Secrets
  "resilio/encrypted/dad.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "resilio/encrypted/projects.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "resilio/encrypted/resources.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "resilio/encrypted/sync.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  ## Read/Write Resilio Sync Secrets
  "resilio/plain/dad.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "resilio/plain/joseph.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "resilio/plain/projects.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "resilio/plain/resources.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];
  "resilio/plain/sync.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];

  # Matrix Secrets
  "matrix/matrix.hillion.co.uk/macaroon_secret_key.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "matrix/matrix.hillion.co.uk/email.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  # Backblaze Secrets
  "backblaze/vm-strangervm-backups-matrix.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  # Restic Secrets
  "restic/b2-backups-matrix.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  # Spotify Secrets
  "spotify/11132032266.age".publicKeys = jake_users ++ [ ts.terminals.jakehillion.gendry ];

  # Drone Secrets
  "drone/gitea_client_secret.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "drone/rpc_secret.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];

  # Mastodon Secrets
  "mastodon/social.hillion.co.uk/otp_secret_file.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "mastodon/social.hillion.co.uk/secret_key_base.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "mastodon/social.hillion.co.uk/vapid_private_key.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
  "mastodon/social.hillion.co.uk/mastodon_at_social.hillion.co.uk.age".publicKeys = jake_users ++ [ ts.strangervm.vm ];
}
