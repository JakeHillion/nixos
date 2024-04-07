{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ./hardware-configuration.nix
  ];

  config = {
    system.stateVersion = "22.05";

    networking.hostName = "vm";
    networking.domain = "strangervm.ts.hillion.co.uk";

    boot.loader.grub = {
      enable = true;
      device = "/dev/sda";
    };

    ## Custom Services
    custom = {
      locations.autoServe = true;
    };

    ## Networking
    networking.interfaces.ens18.ipv4.addresses = [{
      address = "10.72.164.3";
      prefixLength = 24;
    }];
    networking.defaultGateway = "10.72.164.1";

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
      trustedInterfaces = lib.mkForce [
        "lo"
        "tailscale0"
      ];
      interfaces = {
        ens18 = {
          allowedTCPPorts = lib.mkForce [
            80 # HTTP 1-2
            443 # HTTPS 1-2
          ];
          allowedUDPPorts = lib.mkForce [
            443 # HTTP 3
          ];
        };
      };
    };

    ## Tailscale
    age.secrets."tailscale/vm.strangervm.ts.hillion.co.uk".file = ../../secrets/tailscale/vm.strangervm.ts.hillion.co.uk.age;
    custom.tailscale = {
      enable = true;
      preAuthKeyFile = config.age.secrets."tailscale/vm.strangervm.ts.hillion.co.uk".path;
      ipv4Addr = "100.110.89.111";
      ipv6Addr = "fd7a:115c:a1e0:ab12:4843:cd96:626e:596f";
    };

    ## Backups
    services.postgresqlBackup.location = "/data/backup/postgres";
  };
}
