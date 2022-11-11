{ config, pkgs, lib, ... }:

{
  system.stateVersion = "22.05";

  networking.hostName = "vm";
  networking.domain = "strangervm.ts.hillion.co.uk";
 
  imports = [
    ../../modules/common/default.nix
    ../../modules/resilio/default.nix
    ../../modules/reverse-proxy/global.nix
    ../../modules/secrets/resilio/encrypted.nix
    ../../modules/secrets/tailscale/vm.strangervm.ts.hillion.co.uk.nix
    ./hardware-configuration.nix
  ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  networking.interfaces.ens18.ipv4.addresses = [{
    address = "10.72.164.3";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.72.164.1";

  ## Resilio Sync (Encrypted)
  services.resilio.enable = true;
  services.resilio.deviceName = "vm.strangervm";
  services.resilio.directoryRoot = "/data/sync";
}

