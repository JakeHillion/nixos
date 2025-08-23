{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
  ];

  config = {
    ## Systemd-boot
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ## Setup but don't enable tang, that depends on the device's location
    custom.tang = {
      networkingModule = "e1000e"; # Intel Gigabit Ethernet typically used in QNAP devices
      secretFile = "/data/disk_encryption.jwe";
      devices = [ "disk0-crypt" "disk1-crypt" ];
    };

    # Delegation
    custom.impermanence.enable = true;
  };
}
