{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.initrd.kernelModules = [
      "virtio_blk"
      "virtio_pci"
      "virtio_scsi"
    ];

    # Tang/Clevis configuration (disabled by default)
    custom.tang = {
      networkingModule = "virtio_net";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" ];
    };

    # Enable impermanence for ephemeral root
    custom.impermanence.enable = true;
  };
}
