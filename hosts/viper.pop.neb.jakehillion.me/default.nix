{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    system.stateVersion = "25.11";

    boot.kernelPackages = pkgs.linuxPackages_latest;

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

    custom.auto_updater.allowReboot = true;

    custom.sched_ext = {
      enable = true;
      scheduler = "scx_lavd";
    };
    services.scx.extraArgs = [ "--powersave" ];

    custom.impermanence.enable = true;
  };
}
