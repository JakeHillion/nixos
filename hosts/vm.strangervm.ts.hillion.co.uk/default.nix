{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common/default.nix
    ../../modules/drone/server.nix
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
      www.global.enable = true;
      services.matrix.enable = true;
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
    };

    ## Resilio Sync (Encrypted)
    custom.resilio.enable = true;
    services.resilio.deviceName = "vm.strangervm";
    services.resilio.directoryRoot = "/data/sync";
    services.resilio.storagePath = "/data/sync/.sync";

    custom.resilio.folders =
      let
        folderNames = [
          "dad"
          "projects"
          "resources"
          "sync"
        ];
        mkFolder = name: {
          name = name;
          secret = {
            name = "resilio/encrypted/${name}";
            file = ../../secrets/resilio/encrypted/${name}.age;
          };
        };
      in
      builtins.map (mkFolder) folderNames;

    ## Backups
    services.postgresqlBackup.location = "/data/backup/postgres";
  };
}
