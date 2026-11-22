{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    system.stateVersion = "26.05";

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
    boot.initrd.kernelModules = [ "dm-integrity" ];
    boot.kernelModules = [ "kvm-intel" ];
    hardware.cpu.intel.updateMicrocode = true;

    services.fstrim.enable = true;

    custom.defaults = true;
    custom.impermanence.enable = true;

    ogygia.nebula.enable = lib.mkForce false;

    custom.tang = {
      enable = true;
      networkingModule = "igc";
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" "disk2-crypt" ];
    };
  };
}
