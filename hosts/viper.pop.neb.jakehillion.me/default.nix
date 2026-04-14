{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    system.stateVersion = "25.05";

    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub = {
      enable = true;

      efiSupport = true;
      device = "nodev";

      mirroredBoots = lib.mkOverride 51 [
        {
          devices = [ "/dev/disk/by-path/pci-0000:01:00.0-nvme-1" ];
          path = "/boot0";
        }
        {
          devices = [ "/dev/disk/by-path/pci-0000:05:00.0-nvme-1" ];
          path = "/boot1";
        }
      ];
    };

    custom.defaults = true;

    custom.tang = {
      enable = true;
      networkingModule = "r8169";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    custom.auto-updater.allowReboot = true;

    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };
    services.scx.extraArgs = [ "--powersave" ];

    custom.impermanence.enable = true;
  };
}
