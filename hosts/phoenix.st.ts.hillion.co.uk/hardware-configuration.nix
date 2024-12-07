# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "ahci" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/mnt/d0" =
    {
      device = "/dev/disk/by-uuid/9136434d-d883-4118-bd01-903f720e5ce1";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d1" =
    {
      device = "/dev/disk/by-uuid/a55d164e-b48e-4a4e-b073-d0768662d3d0";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d2" =
    {
      device = "/dev/disk/by-uuid/82b82c66-e6e6-4b76-a5ef-8adea33dbe18";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d3" =
    {
      device = "/dev/disk/by-uuid/6566588a-9399-4b35-a18c-060de0ee8431";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d4" =
    {
      device = "/dev/disk/by-uuid/850ce5db-4245-428a-a66d-2647abf62a4c";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d5" =
    {
      device = "/dev/disk/by-uuid/78bc5c57-d554-43c5-9a84-14e3dc52b1b3";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d6" =
    {
      device = "/dev/disk/by-uuid/b461e07d-39ab-46b4-b1d1-14c2e0791915";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  fileSystems."/mnt/d7" =
    {
      device = "/dev/disk/by-uuid/eb8d32d0-e506-449b-8dbc-585ba05c4252";
      fsType = "btrfs";
      options = [ "noatime" ];
    };

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp4s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp8s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
