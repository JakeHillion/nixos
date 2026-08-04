{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    ## Mirrored grub
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub = {
      enable = true;

      efiSupport = true;
      device = "nodev"; # leave it to mirroredBoots

      mirroredBoots = lib.mkOverride 51 [
        {
          devices = [ "/dev/disk/by-path/pci-0000:00:17.0-ata-1.0" ];
          path = "/boot0";
        }
        {
          devices = [ "/dev/disk/by-path/pci-0000:00:17.0-ata-2.0" ];
          path = "/boot1";
        }
      ];
    };

    ## Setup but don't enable tang, that depends on the device's location
    custom.tang = {
      networkingModule = "igb";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    # Delegation
    custom.impermanence.enable = true;
  };
}
