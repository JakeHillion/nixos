# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/cb48d4ed-d268-490c-9977-2b5d31ce2c1b";
      fsType = "btrfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/BC57-0AF6";
      fsType = "vfat";
    };

  # fileSystems."/mnt/d0" =
  #   {
  #     device = "/dev/disk/by-uuid/b424c997-4be6-42f3-965a-f5b3573a9cb3";
  #     fsType = "btrfs";
  #   };

  fileSystems."/mnt/d1" =
    {
      device = "/dev/disk/by-uuid/9136434d-d883-4118-bd01-903f720e5ce1";
      fsType = "btrfs";
    };

  fileSystems."/mnt/d2" =
    {
      device = "/dev/disk/by-uuid/a55d164e-b48e-4a4e-b073-d0768662d3d0";
      fsType = "btrfs";
    };

  fileSystems."/mnt/d3" =
    {
      device = "/dev/disk/by-uuid/82b82c66-e6e6-4b76-a5ef-8adea33dbe18";
      fsType = "btrfs";
    };

  fileSystems."/mnt/d4" =
    {
      device = "/dev/disk/by-uuid/6566588a-9399-4b35-a18c-060de0ee8431";
      fsType = "btrfs";
    };

  fileSystems."/mnt/d5" =
    {
      device = "/dev/disk/by-uuid/850ce5db-4245-428a-a66d-2647abf62a4c";
      fsType = "btrfs";
    };

  fileSystems."/mnt/d6" =
    {
      device = "/dev/disk/by-uuid/78bc5c57-d554-43c5-9a84-14e3dc52b1b3";
      fsType = "btrfs";
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp7s0.useDHCP = lib.mkDefault true;

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
