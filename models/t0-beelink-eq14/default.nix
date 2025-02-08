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
          devices = [ "/dev/nvme0n1" ];
          path = "/boot0";
        }
        {
          devices = [ "/dev/nvme1n1" ];
          path = "/boot1";
        }
      ];
    };

    ## Zswap
    boot.kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=20"
    ];

    ## Setup but don't enable tang, that depends on the device's location
    custom.tang = {
      networkingModule = "r8169";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    # Delegation
    custom.impermanence.enable = true;
  };
}
