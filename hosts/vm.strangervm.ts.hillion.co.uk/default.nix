{ config, pkgs, lib, ... }:

{
  config.system.stateVersion = "22.05";

  config.networking.hostName = "vm";
  config.networking.domain = "strangervm.ts.hillion.co.uk";

  imports = [
    ../../modules/common/default.nix
    ../../modules/matrix/default.nix
    ../../modules/resilio/default.nix
    ../../modules/www/global.nix
    ./hardware-configuration.nix
  ];

  config.boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  ## Static Networking
  config.networking.interfaces.ens18.ipv4.addresses = [{
    address = "10.72.164.3";
    prefixLength = 24;
  }];
  config.networking.defaultGateway = "10.72.164.1";

  ## Tailscale
  config.age.secrets."tailscale/vm.strangervm.ts.hillion.co.uk".file = ../../secrets/tailscale/vm.strangervm.ts.hillion.co.uk.age;
  config.tailscalePreAuth = config.age.secrets."tailscale/vm.strangervm.ts.hillion.co.uk".path;

  ## Resilio Sync (Encrypted)
  config.services.resilio.enable = true;
  config.services.resilio.deviceName = "vm.strangervm";
  config.services.resilio.directoryRoot = "/data/sync";
  config.services.resilio.storagePath = "/data/sync/.sync";

  config.age.secrets."resilio/encrypted/dad" = {
    file = ../../secrets/resilio/encrypted/dad.age;
    owner = "rslsync";
    group = "rslsync";
  };
  config.age.secrets."resilio/encrypted/projects" = {
    file = ../../secrets/resilio/encrypted/projects.age;
    owner = "rslsync";
    group = "rslsync";
  };
  config.age.secrets."resilio/encrypted/resources" = {
    file = ../../secrets/resilio/encrypted/resources.age;
    owner = "rslsync";
    group = "rslsync";
  };
  config.age.secrets."resilio/encrypted/sync" = {
    file = ../../secrets/resilio/encrypted/sync.age;
    owner = "rslsync";
    group = "rslsync";
  };

  config.resilioFolders = [
    { name = "dad"; secretFile = config.age.secrets."resilio/encrypted/dad".path; }
    { name = "projects"; secretFile = config.age.secrets."resilio/encrypted/projects".path; }
    { name = "resources"; secretFile = config.age.secrets."resilio/encrypted/resources".path; }
    { name = "sync"; secretFile = config.age.secrets."resilio/encrypted/sync".path; }
  ];

  ## Backups
  config.services.postgresqlBackup.location = "/data/backup/postgres";
}
