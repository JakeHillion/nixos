{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    # Boot configuration
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Vultr VPS uses virtio drivers
    boot.initrd.kernelModules = [
      "virtio_blk"
      "virtio_pci"
      "virtio_scsi"
      "virtio_net"
    ];

    # Tang/Clevis configuration (disabled by default)
    custom.tang = {
      networkingModule = "virtio_net";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" ];
    };

    # Enable impermanence for ephemeral root
    custom.impermanence.enable = true;

    # Reset root subvolume on boot for ephemeral root
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      mkdir -p /mnt

      # Mount btrfs root to /mnt
      mount -o subvol=/ /dev/mapper/disk0-crypt /mnt

      # Delete existing subvolumes under /root
      btrfs subvolume list -o /mnt/root |
      cut -f9 -d' ' |
      while read subvolume; do
        echo "deleting /$subvolume subvolume..."
        btrfs subvolume delete "/mnt/$subvolume"
      done &&
      echo "deleting /root subvolume..." &&
      btrfs subvolume delete /mnt/root

      echo "restoring blank /root subvolume..."
      btrfs subvolume snapshot /mnt/root-blank /mnt/root

      # Unmount and continue boot process
      umount /mnt
    '';

    # Networking - Using DHCP which Vultr provides
    networking.useDHCP = lib.mkDefault true;
  };
}
