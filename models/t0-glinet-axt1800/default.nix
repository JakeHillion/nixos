{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    # initrd but no bootloader. we'll kexec from the OpenWRT installation for now.
    boot.initrd.enable = true;
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;

    ## Custom kernel
    ##
    ## This kernel is ancient and not LTS. The kernel this device ships with is
    ## `Linux GL-AXT1800 4.4.60 #0 SMP PREEMPT Sun Dec 15 15:18:01 2024 armv7l
    ## GNU/Linux`. Start with the oldest kernel in nixpkgs, 4_14, and work our
    ## way forwards after there's a baseline.
    # boot.kernelPackages = pkgs.linuxPackages_4_14.override {
    #   kernelConfig = builtins.readFile ./kconfig;
    # };

    ## Enable zram for 512MB of RAM. Bad idea to use disk backed swap on the SD card.
    # TODO: enable or remove me
    # zramSwap = {
    #   enable = true;
    #   memoryPercent = 200;
    #   algorithm = "zstd";
    # };

    ## Reset root before mounting for impermanence
    # TODO: enable me
    # boot.initrd.systemd.services.rollback = {
    #   description = "Rollback BTRFS root subvolume to a pristine state";
    #   wantedBy = [
    #     "initrd.target"
    #   ];
    #   before = [
    #     "sysroot.mount"
    #   ];
    #   unitConfig.DefaultDependencies = "no";
    #   serviceConfig.Type = "oneshot";
    #   script = ''
    #     echo "Mounting SD card root..."
    #     mkdir -p /mnt
    #     mount /dev/mmcblk0p2 /mnt

    #     echo "Backing up old root subvolume..."
    #     mkdir -p /mnt/data/.oldroots

    #     # this only gets the root. any subvolumes created below it will be lost.
    #     # TODO: confirm this device has an RTC and that this date will vary
    #     btrfs subvolume snapshot /mnt/impermanence_root /mnt/data/.oldroots/$(date --iso-8601=minutes)

    #     echo "Wiping old root subvolume..."
    #     btrfs subvolume delete -R /mnt/impermanence_root

    #     echo "Restoring blank root subvolume..."
    #     btrfs subvolume snapshot /mnt/impermanence_root_empty /mnt/impermanence_root

    #     echo "Cleaning up..."
    #     umount /mnt
    #   '';
    # };
  };
}
