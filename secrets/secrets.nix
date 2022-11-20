let
  jake-gentoo = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw4lgH20nfuchDqvVf0YciqN0GnBw5hfh8KIun5z0P7wlNgVYnCyvPvdIlGf2Nt1z5EGfsMzMLhKDOZkcTMlhupd+j2Er/ZB764uVBGe1n3CoPeasmbIlnamZ12EusYDvQGm2hVJTGQPPp9nKaRxr6ljvTMTNl0KWlWvKP4kec74d28MGgULOPLT3HlAyvUymSULK4lSxFK0l97IVXLa8YwuL5TNFGHUmjoSsi/Q7/CKaqvNh+ib1BYHzHYsuEzaaApnCnfjDBNexHm/AfbI7s+g3XZDcZOORZn6r44dOBNFfwvppsWj3CszwJQYIFeJFuMRtzlC8+kyYxci0+FXHn jake@jake-gentoo";
  jake-mbp = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAyFsYYjLZ/wyw8XUbcmkk6OKt2IqLOnWpRE5gEvm3X0V4IeTOL9F4IL79h7FTsPvi2t9zGBL1hxeTMZHSGfrdWaMJkQp94gA1W30MKXvJ47nEVt0HUIOufGqgTTaAn4BHxlFUBUuS7UxaA4igFpFVoPJed7ZMhMqxg+RWUmBAkcgTWDMgzUx44TiNpzkYlG8cYuqcIzpV2dhGn79qsfUzBMpGJgkxjkGdDEHRk66JXgD/EtVasZvqp5/KLNnOpisKjR88UJKJ6/buV7FLVra4/0hA9JtH9e1ecCfxMPbOeluaxlieEuSXV2oJMbQoPP87+/QriNdi/6QuCHkMDEhyGw== jake@jake-mbp";
  users = [ jake-gentoo jake-mbp ];

  vm_strangervm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINb9mgyD/G3Rt6lvO4c0hoaVOlLE8e3+DUfAoB1RI5cy root@vm";
  microserver_home = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPOCPqXm5a+vGB6PsJFvjKNgjLhM5MxrwCy6iHGRjXw root@microserver";
  microserver_parents = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0cjjNQPnJwpu4wcYmvfjB1jlIfZwMxT+3nBusoYQFr root@microserver";
  systems = [ vm_strangervm microserver_home microserver_parents ];
in
{
  # Tailscale Pre-Auth Keys
  "tailscale/vm.strangervm.ts.hillion.co.uk.age".publicKeys = users ++ [ vm_strangervm ];
  "tailscale/microserver.home.ts.hillion.co.uk.age".publicKeys = users ++ [ microserver_home ];
  "tailscale/microserver.parents.ts.hillion.co.uk.age".publicKeys = users ++ [ microserver_parents ];

  # Resilio Sync Secrets
  ## Encrypted Resilio Sync Secrets
  "resilio/encrypted/dad.age".publicKeys = users ++ [ vm_strangervm ];
  "resilio/encrypted/projects.age".publicKeys = users ++ [ vm_strangervm ];
  "resilio/encrypted/resources.age".publicKeys = users ++ [ vm_strangervm ];
  "resilio/encrypted/sync.age".publicKeys = users ++ [ vm_strangervm ];

  ## Read/Write Resilio Sync Secrets
  "resilio/plain/dad.age".publicKeys = users;
  "resilio/plain/joseph.age".publicKeys = users;
  "resilio/plain/projects.age".publicKeys = users;
  "resilio/plain/resources.age".publicKeys = users;
  "resilio/plain/sync.age".publicKeys = users;
}
