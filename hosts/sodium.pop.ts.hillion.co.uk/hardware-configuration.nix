# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "usbhid" "usb_storage" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/417B-1063";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  fileSystems."/nix" =
    {
      device = "/dev/disk/by-uuid/48ae82bd-4d7f-4be6-a9c9-4fcc29d4aac0";
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

  fileSystems."/data" =
    {
      device = "/dev/disk/by-uuid/48ae82bd-4d7f-4be6-a9c9-4fcc29d4aac0";
      fsType = "btrfs";
      options = [ "subvol=data" ];
    };

  fileSystems."/cache" =
    {
      device = "/dev/disk/by-uuid/48ae82bd-4d7f-4be6-a9c9-4fcc29d4aac0";
      fsType = "btrfs";
      options = [ "subvol=cache" ];
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enu1u4.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
